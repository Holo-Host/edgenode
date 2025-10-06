use ipnet::IpNet;
use serde_derive::{Deserialize, Serialize};
use serde_with::serde_as;
use std::net::IpAddr;

pub mod install;
pub mod models;

/// Configuration file to define how HolOS should be run and where it should persist itself or its
/// data, as well as a variety of security and network related concerns.
#[derive(Debug, Serialize, Deserialize)]
pub struct HolosConfig {
    /// Configuration content for persistence of data.
    pub storage: StorageConfig,
    /// Network content defining the configuration for network interfaces.
    pub network: NetworkConfig,
    /// Security-related configuration content.
    pub security: SecurityConfig,
}

/// Configuration for data/system persistence.
#[derive(Debug, Serialize, Deserialize)]
pub struct StorageConfig {
    /// Partition to install Holos to.
    pub install_partition: Option<String>,
    /// Partition to persist Holo and Holochain data to.
    pub persist_partition: Option<String>,
}

/// Network interface and nameserver configuration.
#[derive(Debug, Serialize, Deserialize)]
pub struct NetworkConfig {
    /// A list of IP address (IPv6 or IPv4) addresses to use as DNS nameservers.
    pub nameservers: Vec<IpAddr>,
    /// A list of network interfaces to bring up on boot.
    pub interfaces: Vec<NetworkInterface>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NetworkInterface {
    /// Identifier for the network interface to be configured. If listed, this will bring the
    /// interface up using DHCPv4 and DHCPv6 by default, but addresses can be specified statically
    /// too if needed.
    // TODO: Should likely be an enum
    pub identifier: DeviceIdentifier,
    /// List of static addresses to assign (IPv6 or IPv4) in cases where DHCP isn't desired.
    pub static_addresses: Vec<InterfaceAddress>,
}

#[serde_as]
#[derive(Debug, Serialize, Deserialize)]
pub enum DeviceIdentifier {
    #[serde(rename = "pci_address")]
    PciAddress {
        /// Identify the network device by its PCI address (safe). Eg, 0000:00:14.1
        address: String,
    },
    #[serde(rename = "virtio")]
    Virtio {
        /// Address on the virtio bus. Eg, 0000:00:03.0/virtio2?
        address: String,
    },
    #[serde(rename = "usb")]
    Usb {
        /// TODO: This probably needs to be the vendor and product IDs, rather than the address,
        /// which is more likely to change. However, if we use vendor/product IDs, a machine with
        /// two USB sticks of the same model could yield inconsistent results.
        address: String,
    },
}

/// Addresses and gateways to assign to a network interface.
#[derive(Debug, Serialize, Deserialize)]
pub struct InterfaceAddress {
    /// An IPv6 or IPv4 CIDR-syntax address/netmask to assign to this interface.
    pub address: IpNet,
    /// The optional IPv6 or IPv4 address of the gateway for this interface.
    pub gateway: Option<IpAddr>,
}

/// Security-related configuration info.
#[derive(Debug, Serialize, Deserialize)]
pub struct SecurityConfig {
    /// Usernames of github users we trust. For each user, we will retrieve all of public ssh keys
    /// published on github by that user, and add those as authorized/trusted keys on the local
    /// instance.
    pub github_usernames: Vec<String>,
    /// If github keys are not available or desired, explicit keys may be specified as a list of
    /// strings.
    pub ssh_keys: Vec<String>,
    /// The root password is disabled by default, with ssh keys being preferred. If a root password
    /// is required or desired, include the hashed password as a string here.
    pub rootpw_hash: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_yaml;
    use std::str::FromStr;

    const TEST_CONFIG: &str = "
storage:
    install_partition: /dev/sda1
    persist_partition: /dev/sda2
network:
    nameservers:
        - 1.1.1.1
    interfaces:
        # The most accurate way to select an interface is by PCI address
        - identifier: !pci_address
            address: '00:14.1'
          static_addresses:
            - address: 10.0.0.100/24
              gateway: 10.0.0.1
            - address: 2001:db8::100/64
security:
    github_usernames:
        - someuser
    ssh_keys:
    rootpw_hash:
";

    #[test]
    /// Smoke test parsing the config file.
    fn config_parse() {
        let c: HolosConfig = serde_yaml::from_str(TEST_CONFIG).unwrap();

        dbg!(&c);

        assert_eq!(c.storage.persist_partition, Some("/dev/sda2".to_string()));
        assert_eq!(c.storage.install_partition, Some("/dev/sda1".to_string()));
        assert_eq!(
            c.network.nameservers[0],
            IpAddr::from_str("1.1.1.1").unwrap()
        );
        assert_eq!(c.network.interfaces.len(), 1);
        assert_eq!(c.network.interfaces[0].static_addresses.len(), 2);
        assert_eq!(c.security.github_usernames.len(), 1);
        assert_eq!(c.security.ssh_keys.len(), 0);
    }
}

/// The arguments passed to the Linux kernel at boot time are presented to the running userspace
/// through the /proc/cmdline interface. This module facilitates the parsing of this string to
/// retrieve and HolOS-specific parameters.
pub mod cmdline {
    use std::fs::File;
    use std::io::{BufRead, BufReader};
    use std::path::Path;

    pub struct CmdLine {
        /// This string contains the location of the configuration file to use, if not the default.
        pub config_file: Option<String>,
        /// This is the github username of a user whose public ssh keys we will retrieve and trust
        /// for the local root user.
        pub github_usernames: Vec<String>,
        /// This flag sets whether we ought to try and install the operating system permanently or
        /// not.
        pub install_flag: bool,
        /// This flag just indicates that we likely booted the live image, rather than from a hard
        /// drive or similar.
        pub live_flag: bool,
    }

    impl CmdLine {
        pub fn from_file(file: &str) -> Result<Self, anyhow::Error> {
            let mut config_file: Option<String> = None;
            let mut github_usernames: Vec<String> = vec![];
            let mut install_flag: bool = false;
            let mut live_flag: bool = false;

            let path = Path::new(file);
            let f = File::open(path)?;
            let reader = BufReader::new(f);
            // There's only ever one line in this file.
            if let Some(cmdline) = reader.lines().next() {
                for arg in cmdline?.split(' ') {
                    // If they specified the location of a config file
                    if let Some(cfg) = arg.strip_prefix("config_file=") {
                        config_file = Some(cfg.to_string());
                    } else if let Some(names) = arg.strip_prefix("github_usernames=") {
                        github_usernames = names.split(',').map(|s| s.to_string()).collect();
                    } else if arg == "install" {
                        install_flag = true;
                    } else if arg == "live" {
                        live_flag = true;
                    }
                }
            }

            Ok(CmdLine {
                config_file,
                github_usernames,
                install_flag,
                live_flag,
            })
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use std::fs;
        use tempfile::NamedTempFile;

        const CMDLINE_WITH_CONFIG_FILE: &str =
            "root=/dev/sda1 ro quiet -- config_file=/etc/holos/configs/holoport.yaml";
        const CMDLINE_WITH_GITHUB_USERS: &str =
            "root=LABEL=holos_root ro crashkernel=xxx,yyy github_usernames=username1,username2";
        const CMDLINE_WITH_INSTALL_FLAG: &str = "root=LABEL=holos_root ro -- install";

        #[test]
        fn test_config_file() {
            // Write a string to a throwaway file and then make sure the above code can parse it.
            let tempfile = NamedTempFile::new().unwrap();
            let filename = tempfile.path();
            fs::write(&filename, CMDLINE_WITH_CONFIG_FILE).unwrap();

            let overrides = CmdLine::from_file(&filename.to_str().unwrap()).unwrap();
            assert_eq!(
                overrides.config_file,
                Some("/etc/holos/configs/holoport.yaml".to_string())
            );
        }

        #[test]
        fn test_github_users() {
            // Write a string to a throwaway file and then make sure the above code can parse it.
            let tempfile = NamedTempFile::new().unwrap();
            let filename = tempfile.path();
            fs::write(&filename, CMDLINE_WITH_GITHUB_USERS).unwrap();

            let overrides = CmdLine::from_file(&filename.to_str().unwrap()).unwrap();
            assert_eq!(overrides.github_usernames, vec!["username1", "username2"]);
        }

        #[test]
        fn test_install_flag() {
            // Write a string to a throwaway file and then make sure the above code can parse it.
            let tempfile = NamedTempFile::new().unwrap();
            let filename = tempfile.path();
            fs::write(&filename, CMDLINE_WITH_INSTALL_FLAG).unwrap();

            let overrides = CmdLine::from_file(&filename.to_str().unwrap()).unwrap();
            assert_eq!(overrides.install_flag, true);
        }

        #[test]
        fn test_no_install_flag() {
            // Write a string to a throwaway file and then make sure the above code can parse it.
            let tempfile = NamedTempFile::new().unwrap();
            let filename = tempfile.path();
            fs::write(&filename, CMDLINE_WITH_GITHUB_USERS).unwrap();

            let overrides = CmdLine::from_file(&filename.to_str().unwrap()).unwrap();
            assert_eq!(overrides.install_flag, false);
        }
    }
}
