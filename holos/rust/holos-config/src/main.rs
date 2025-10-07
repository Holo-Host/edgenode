use clap::{Parser, Subcommand};
use holos_config::{HolosConfig, cmdline::CmdLine, install::do_install, models::ModelConfig};
use local_ip_address::list_afinet_netifas;
use log::info;
use serde::Deserialize;
use std::env;
use std::fs;
use std::fs::{File, OpenOptions};
use std::io::{BufReader, Write};
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::Path;
use syslog::Facility;

#[derive(Debug, Parser)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
    #[arg(short, long, default_value_t = false)]
    syslog: bool,
}

#[derive(Debug, Subcommand)]
enum Commands {
    Configure {},
    TrustedKeys {},
    EtcIssue {},
    Install {},
}

/// The structure we get keys from github in
#[derive(Debug, Deserialize)]
pub struct GithubKeys {
    pub id: i32,
    pub key: String,
    pub created_at: String,
}

// We allow the user to tell us which configuration file to use through things like boot-time
// parameters. We also try to find the right configuration file for specific models of machine that
// we're familiar with (such as holoports). If we can't find a suitable one, we fall back to
// something that's likely to work.
const DEFAULT_CONFIG_FILE_PATH: &str = "/etc/holos/configs/default.yaml";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    // Set up logging. When running locally, use env_logger, but when running in production, send
    // everything to syslog for easier support.
    match cli.syslog {
        true => syslog::init(
            Facility::LOG_USER,
            log::LevelFilter::Debug,
            Some("holos-config"),
        )?,
        false => env_logger::init(),
    }

    let cmdline_path = match env::var("CMDLINE_PATH") {
        Ok(v) => v,
        Err(_) => "/proc/cmdline".to_string(),
    };
    info!("Using {} as kernel command line source", cmdline_path);
    let overrides = CmdLine::from_file(&cmdline_path)?;

    let mut config_file_path = DEFAULT_CONFIG_FILE_PATH.to_string();
    // This is the case where the user has told us the path to an explicit configuration file,
    // likely via a boot-time command line argument.
    if let Some(config_file) = overrides.config_file {
        config_file_path = config_file.to_owned();
    } else if let Some(model_config) = ModelConfig::config_file() {
        config_file_path = model_config.to_owned();
    }
    info!("Configuration file {} selected.", config_file_path);
    let path = Path::new(&config_file_path);
    let file = File::open(path)?;
    let reader = BufReader::new(file);

    let mut config: HolosConfig = serde_yaml::from_reader(reader)?; // Use from_reader

    if !overrides.github_usernames.is_empty() {
        config.security.github_usernames = overrides.github_usernames.clone();
    }

    match &cli.command {
        Commands::TrustedKeys {} => {
            // Retrieve keys from github, if desired.
            let mut keys = String::new();
            for user in config.security.github_usernames {
                info!("Downloading keys for github user: {}", user);
                let uri = format!("https://api.github.com/users/{}/keys", user);
                info!("URI: {}", uri);
                let client = reqwest::Client::new();
                /*
                let res = client
                    .get(uri)
                    .header("User-Agent", "HolOS Configurator")
                    .send()
                    .await?;*/
                //info!("{}", res.text().await?);
                let res = client
                    .get(uri)
                    .header("User-Agent", "HolOS Configurator")
                    .send()
                    .await?
                    .json::<Vec<GithubKeys>>()
                    .await?;

                for key in res {
                    keys += format!("{} {}_{}\n", key.key, user, key.id).as_str();
                }
            }
            fs::create_dir_all("/root/.ssh")?;
            fs::write("/root/.ssh/authorized_keys", keys)?;
            let metadata = fs::metadata("/root/.ssh")?;
            let mut permissions = metadata.permissions();
            permissions.set_mode(0o700);
            fs::set_permissions("/root/.ssh", permissions)?;
            let metadata = fs::metadata("/root/.ssh/authorized_keys")?;
            let mut permissions = metadata.permissions();
            permissions.set_mode(0o600);
            fs::set_permissions("/root/.ssh/authorized_keys", permissions)?;
        }
        Commands::EtcIssue {} => {
            let mut issue: String;
            let version = fs::read_to_string("/etc/holos-version")?;
            issue = format!("\n\nHolOS Version: {}\n", version);
            issue += format!("Live boot: {}\n", overrides.live_flag).as_str();
            issue += format!(
                "Superuser trusts keys from github users: {}\n",
                config.security.github_usernames.join(",")
            )
            .as_str();
            issue += "IP address configuration:\n";
            let network_interfaces = list_afinet_netifas();
            match network_interfaces {
                Ok(nics) => {
                    for (name, ip) in nics {
                        if name != "lo" && name != "virbr0" && name != "docker0" {
                            issue += format!("    {} => {}\n", name, ip).as_str();
                        }
                    }
                }
                Err(_) => {
                    issue += format!("Unable to retrieve IP addresses.\n").as_str();
                }
            }
            issue += "\n\n";
            issue += "TODO: add model info here\n";

            fs::write("/etc/issue", issue)?;
        }
        Commands::Install {} => {
            do_install(&config)?;
        }
        Commands::Configure {} => {
            let interfaces_path = match env::var("INTERFACES_PATH") {
                Ok(v) => v,
                Err(_) => "/etc/network/interfaces.d".to_string(),
            };
            info!(
                "Using {} as network interface definition path",
                interfaces_path
            );
            // Create network interface configurations
            for iface in config.network.interfaces {
                info!("Configuring interface: {:?}", iface.identifier);
                if !iface.static_addresses.is_empty() {
                    // Adding support for static IPs isn't hard, we're just time constrained. The process
                    // would still be the same -- writing the configuration to the interfaces files.
                    eprintln!("Static addresses have not yet been implemented.");
                    info!("Static addresses have not yet been implemented.");
                    // Fall through and use DHCP anyway
                }
                let interface_name = match iface.identifier {
                    holos_config::DeviceIdentifier::PciAddress { address } => {
                        // Given that all of the network drivers have been loaded at this point, we can
                        // take a look at the PCI device specified by the address in the configuration
                        // file, and map it back to an interface name. This will work regardless of driver
                        // load order, or which network interface device naming convention is employed.
                        let net_path = format!("/sys/bus/pci/devices/{}/net", address);
                        info!("Looking for interface name for {} in {}", address, net_path);
                        let mut entries = fs::read_dir(&net_path)?;
                        // There is only ever one entry in this directory.
                        let mut ret = String::new();
                        if let Some(entry) = entries.next() {
                            let entry = entry?;
                            info!(
                                "Using interface name {} for address {}",
                                entry.file_name().display(),
                                address
                            );
                            ret = format!("{}", entry.file_name().display());
                        }
                        Some(ret)
                    }
                    holos_config::DeviceIdentifier::Virtio { address } => {
                        // Not currently supported. Assume the name `eth0`
                        info!(
                            "Virtio devices not currently fully implemented for device {}",
                            address
                        );
                        None
                    }
                    holos_config::DeviceIdentifier::Usb { address } => {
                        // Not currently supported. Assume the name `eth0`
                        info!(
                            "USB devices not currently fully implemented for device {}",
                            address
                        );
                        None
                    }
                };
                if let Some(interface) = interface_name {
                    // Magic OpenRC ju-ju. Try and create the symlink. If it fails, continue
                    // anyway.
                    symlink(
                        "/etc/init.d/net.lo",
                        format!("/etc/init.d/net.{}", interface),
                    )
                    .ok();
                    let netifrc_stanza = format!("config_{}=\"dhcp\"\n", interface);
                    let mut file = OpenOptions::new()
                        .append(true)
                        .create(false)
                        .open("/etc/conf.d/net")?;
                    file.write_all(netifrc_stanza.as_bytes())?;
                } else {
                    info!("Unable to determine interface name for interface. Skipping.");
                    continue;
                }
            }
        }
    }

    Ok(())
}
