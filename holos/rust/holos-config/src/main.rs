use clap::{Parser, Subcommand};
use holos_config::{
    HolosConfig, UpdateConfig, cmdline::CmdLine, models::Model, models::ModelConfig,
    update::Updater, utils::cmd_stdin,
};
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
    RootPassword {},
    EtcIssue {},
    Install {},
    DetectModel {},
    QueryModel {},
    Update {},
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

// This is the configuration file written by us after changes have been made.
const LOCAL_CONFIG_FILE_PATH: &str = "/etc/holos/configs/local.yaml";

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

    // First, we try to discover what model we're running on. This just gives us a set of sensible
    // defaults for the most common cases, with the possibility to override everything, as needed.
    let platform_model = match Model::detect_model() {
        Ok(model) => {
            info!("Detected model: {}", model);
            model
        }
        Err(e) => {
            // Anything to do with models is best-case as a way to provide defaults. Not being able
            // to discover the model shouldn't be a show stopper.
            info!("Failed to detect model with error: {}", e);
            Model::Unknown
        }
    };

    let cmdline_path = match env::var("CMDLINE_PATH") {
        Ok(v) => v,
        Err(_) => "/proc/cmdline".to_string(),
    };
    info!("Using {} as kernel command line source", cmdline_path);
    let overrides = CmdLine::from_file(&cmdline_path)?;

    // Order of precedence for various configuration file paths:
    //  1. Specified on the kernel command line -- highest precedence.
    //  2. Saved local configuration file
    //  3. Per model default configuration file
    //  4. Global default configuration file (default.yaml)
    let mut config_file_path = DEFAULT_CONFIG_FILE_PATH.to_string();
    // This is the case where the user has told us the path to an explicit configuration file,
    // likely via a boot-time command line argument.
    if let Some(config_file) = overrides.config_file {
        config_file_path = config_file.to_owned();
    } else if Path::new(LOCAL_CONFIG_FILE_PATH).exists() {
        config_file_path = LOCAL_CONFIG_FILE_PATH.to_string();
    } else if let Some(model_config) = ModelConfig::config_file(&platform_model) {
        config_file_path = model_config.to_owned();
    }
    info!("Configuration file {} selected.", config_file_path);
    let path = Path::new(&config_file_path);
    let file = File::open(path)?;
    let reader = BufReader::new(file);

    let mut config: HolosConfig = serde_yaml::from_reader(reader)?; // Use from_reader
    let mut config_changed: bool = false;

    // Take into consideration any overrides provided on the kernel command line
    if !overrides.github_usernames.is_empty() {
        config.security.github_usernames = overrides.github_usernames.clone();
        config_changed = true;
    }

    if !overrides.ssh_pubkeys.is_empty() {
        config.security.ssh_keys = overrides.ssh_pubkeys.clone();
        config_changed = true;
    }

    if !overrides.rootpw_hash.is_empty() {
        config.security.rootpw_hash = Some(overrides.rootpw_hash.clone());
        config_changed = true;
    }

    // Write new configuration file with overrides here.
    if config_changed {
        // allow the path to be overriden for testing when writing.
        let local_config = match env::var("LOCAL_CONFIG_FILE") {
            Ok(local) => local,
            Err(_) => LOCAL_CONFIG_FILE_PATH.to_string(),
        };
        info!("Writing local configuration file to {}", local_config);
        let config_string = serde_yaml::to_string(&config)?;
        fs::write(local_config, config_string)?;
    }

    match &cli.command {
        Commands::DetectModel {} => {
            println!("{}", platform_model);
        }
        Commands::QueryModel {} => {
            // This just displays some config stuff in a bourne-shell compatible syntax to eval.
            println!("MODEL=\"{}\"", platform_model);
            if let Some(system_device) = config.storage.system_device {
                println!("SYSTEM_DEVICE=\"{}\"", system_device);
            }
            if let Some(data_device) = config.storage.data_device {
                println!("DATA_DEVICE=\"{}\"", data_device);
            }
        }
        Commands::RootPassword {} => {
            if let Some(hash) = config.security.rootpw_hash {
                info!("Root password hash passed in. Setting it.");
                // Normally, it'd be better to use native Rust code to edit a file like this, but
                // the passwd and shadow files have some particular semantics about permissions,
                // syntax and locking. The `chpasswd` tool handles all of that and reduces the
                // changes of us bricking the machine.
                let input = format!("root:{}", hash);
                let system_root = match env::var("PASSWD_SYSTEM_ROOT") {
                    Ok(v) => v,
                    Err(_) => "/".to_string(),
                };
                let args = vec!["-e", "-R", &system_root];
                cmd_stdin("chpasswd", &args, input)?;
            }
        }
        Commands::TrustedKeys {} => {
            // XXX: Important! When updating any of this code, ensure that the top-level
            // support/user documentation is updated to reflect any new behaviour. That
            // documentation lives at the top of `lib.rs`.
            const DEFAULT_AUTH_KEYS_DIR: &str = "/root/.ssh";
            let trusted_keys_dir = match env::var("AUTHORIZED_KEYS_DIR") {
                Ok(v) => v,
                Err(_) => DEFAULT_AUTH_KEYS_DIR.to_string(),
            };
            let trusted_keys_path = format!("{}/authorized_keys", trusted_keys_dir);
            let mut keys = String::new();
            for user in config.security.github_usernames {
                info!("Downloading keys for github user: {}", user);
                let mut count = 0;
                let uri = format!("https://api.github.com/users/{}/keys", user);
                info!("URI: {}", uri);
                let client = reqwest::Client::new();
                let res = client
                    .get(uri)
                    .header("User-Agent", "HolOS Configurator")
                    .send()
                    .await?
                    .json::<Vec<GithubKeys>>()
                    .await?;

                for key in res {
                    keys += format!("{} {}_{}\n", key.key, user, key.id).as_str();
                    count += 1;
                }

                info!("Downloaded {} keys for user {}", count, user);
            }

            // Now loop through and add and keys explicitly passed on the kernel command line or
            // stored in the config file.
            let mut key_num = 0;
            for key in config.security.ssh_keys {
                info!("Adding explicit public key: {}", key);
                key_num += 1;
                keys += format!("{} explicit_{}\n", key, key_num).as_str();
            }
            fs::create_dir_all(&trusted_keys_dir)?;
            fs::write(&trusted_keys_path, keys)?;
            // OpenSSH has strict requirements about the permissions of the trusted keys file and
            // the directory containing it.
            let metadata = fs::metadata(&trusted_keys_dir)?;
            let mut permissions = metadata.permissions();
            permissions.set_mode(0o700);
            fs::set_permissions(&trusted_keys_dir, permissions)?;
            let metadata = fs::metadata(&trusted_keys_path)?;
            let mut permissions = metadata.permissions();
            permissions.set_mode(0o600);
            fs::set_permissions(&trusted_keys_path, permissions)?;
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
                    issue += "Unable to retrieve IP addresses.\n";
                }
            }
            issue += "\n\n";
            issue += format!("Hardware Model: {}", platform_model).as_str();
            issue += "\n\n";

            fs::write("/etc/issue", issue)?;
        }
        Commands::Install {} => {
            // TODO: temporarily still incomplete.
            //Installer::do_install(&config, &platform_model)?;
        }
        Commands::Update {} => {
            Updater::do_update(&config.updates).await?;
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
                    // TODO: This is not necessary for each boot when the OS is installed. We
                    // should first check for a `config_XXX` line for our interface first, and
                    // replace it if present, or append it if not. The code below is fine. It just
                    // appends a duplicate line each boot.
                    let netifrc_stanza = format!(
                        "config_{}=\"dhcp\"\nudhcpc_{}=\"-b -t 7\"\n",
                        interface, interface
                    );
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
