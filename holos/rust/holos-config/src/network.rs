//! Network related modules

use crate::{DeviceIdentifier, HolosConfig};
use anyhow::Error;
use lazy_static::lazy_static;
use log::info;
use std::env;
use std::fs;
use std::fs::{OpenOptions, Permissions};
use std::io::Write;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::Path;
use tera::{Context, Tera};

// compile templates into the binary
lazy_static! {
    pub static ref TERA: Tera = {
        let tera = match Tera::new("/etc/holos/templates/**/*.conf") {
            Ok(t) => t,
            Err(e) => {
                println!("Template parse error: {}", e);
                ::std::process::exit(1)
            }
        };
        tera
    };
}

pub struct Network {}

impl Network {
    /// This function takes a defined network configuration and writes the relevant pieces to te
    /// right configuration files to allow them to be brought up in order during the HolOS boot
    /// process.
    pub fn configure_network(config: &HolosConfig) -> Result<(), Error> {
        let interfaces_path = match env::var("INTERFACES_PATH") {
            Ok(v) => v,
            Err(_) => "/etc/network/interfaces.d".to_string(),
        };
        info!(
            "Using {} as network interface definition path",
            interfaces_path
        );
        // Create network interface configurations
        for iface in &config.network.interfaces {
            info!("Configuring interface: {:?}", iface.identifier);
            if !iface.static_addresses.is_empty() {
                // Adding support for static IPs isn't hard, we're just time constrained. The process
                // would still be the same -- writing the configuration to the interfaces files.
                eprintln!("Static addresses have not yet been implemented.");
                info!("Static addresses have not yet been implemented.");
                // Fall through and use DHCP anyway
            }
            let interface_name = match &iface.identifier {
                DeviceIdentifier::PciAddress { address } => {
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
                DeviceIdentifier::Virtio { address } => {
                    // Not currently supported. Assume the name `eth0`
                    info!(
                        "Virtio devices not currently fully implemented for device {}",
                        address
                    );
                    None
                }
                DeviceIdentifier::Usb { address } => {
                    // Not currently supported. Assume the name `eth0`
                    info!(
                        "USB devices not currently fully implemented for device {}",
                        address
                    );
                    None
                }
            };
            if let Some(interface) = interface_name {
                info!("Writing interface config for {}", interface);
                Self::write_interface_config(&interface)?;
            } else {
                info!("Unable to determine interface name for interface. Skipping.");
                continue;
            }
        }

        Ok(())
    }

    const OPENRC_LINK_BASE: &str = "/etc/init.d/net";
    const OPENRC_NET_FILE: &str = "/etc/conf.d/net";
    /// Writes required symlinks and configuration files required to have OpenRC bring up an
    /// interface. Currently only supports DHCP and should be changed in future to support static
    /// IPv4 and IPv6 addressing.
    fn write_interface_config(interface: &str) -> Result<(), Error> {
        let src_iface = format!("{}.lo", Self::OPENRC_LINK_BASE);
        let dst_iface = format!("{}.{}", Self::OPENRC_LINK_BASE, interface);
        info!("Symlink {} => {}", src_iface, dst_iface);
        symlink(src_iface, dst_iface)?;

        // The lines we need to write to the network configuration file.
        let netifrc_stanza = format!(
            "config_{iface}=\"dhcp\"\nudhcpc_{iface}=\"-b -t 7\"\n",
            iface = interface
        );

        // We overwrite the file each time, leaving us with only the last interface configured. We
        // should change this in future, so that we can potentially support more than one
        // interface.
        info!("Writing network config to {}", Self::OPENRC_NET_FILE);
        let mut file = OpenOptions::new()
            .append(true)
            .create(true)
            .open(Self::OPENRC_NET_FILE)?;
        file.write_all(netifrc_stanza.as_bytes())?;
        Ok(())
    }

    /// This function writes all of the relevant Wi-Fi configuration to the relevant files to allow
    /// everything to come up during HolOS boot.
    pub fn wifi_config(config: &HolosConfig) -> Result<(), Error> {
        let mut wpa_ssid = String::new();
        let mut wpa_psk = String::new();

        if let Some(wireless) = &config.network.wireless {
            wpa_ssid = wireless.ssid.clone();
            wpa_psk = wireless.wpa_psk.clone();
        }

        info!("Asked to join Wi-Fi network with SSID '{}'", wpa_ssid);

        // tera templating context
        let mut context = Context::new();
        context.insert("wpa_ssid", &wpa_ssid);
        context.insert("wpa_psk", &wpa_psk);

        let rendered_config = match wpa_psk.is_empty() {
            true => TERA.render("wpa_supplicant-insecure.conf", &context)?,
            false => TERA.render("wpa_supplicant-wpa2.conf", &context)?,
        };

        let config_path = match env::var("WPA_SUPPLICANT_CONFIG") {
            Ok(v) => v,
            Err(_) => "/etc/wpa_supplicant.conf".to_string(),
        };
        info!("Writing WPA Supplicant configuration to {}", config_path);

        let path = Path::new(&config_path);
        let mut opts = OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        let mut file = opts.open(path)?;
        file.write_all(rendered_config.as_bytes())?;
        fs::set_permissions(path, Permissions::from_mode(0o600))?;

        // TODO: We also hard-code this to be the first interface name that's likely to be
        // assigned. This should really be done by having the user select the interface by its
        // vendor and device ID.
        info!("Writing wlan0 interface configuration");
        Self::write_interface_config("wlan0")?;

        Ok(())
    }
}
