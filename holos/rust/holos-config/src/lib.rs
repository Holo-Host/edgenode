//! # HolOS kernel command line
//!
//! At either boot menu (the boot menu from the hybrid ISO image, or the GRUB menu when installed),
//! it is possible to add parameters to the kernel boot command line to alter the way the kernel
//! operates, and also to control parts of the HolOS system.
//!
//! This section describes the available kernel command line parameters that are supported by HolOS
//! for overriding defaults. _This is important for configuring the edge node security until HolOS'
//! interactive installer has been completed._
//!
//! To append new parameters:
//! * For the hybrid ISO boot (the blue boot menu), select the menu option you wish to boot, and
//! hit the `<TAB>` key. It will display the current kernel command line, and you can add any of
//! the parameters below that you choose.
//! * For the GRUB boot menu (the black and white one), select the menu option you wish to boot,
//! and hit the `'e'` key. In the editor window that appears, navigate to the line that starts with
//! `linux ....`, and append your desired options to the end of that line, and hit `Ctrl-X` to boot
//! it when ready.
//!
//! _Note: whilst all of the options will be described here, it is anticipated that the most common
//! use case will involve appending just the parameter to specify a set of Github usernames for
//! users that this system will trust to log in (by way of their published public ssh keys._
//!
//! ## `github_usernames` kernel parameter
//!
//! When booting from the hybrid ISO image burned to a USB stick or CD/DVD, it is recommended to
//! pass in the `github_usernames` parameter. This gives HolOS a list of Github usernames whose
//! public SSH keys should be downloaded and trusted by the root user. This gives the holoport
//! owner the ability to provide a way to log into the edge node and start jobs, etc.
//!
//! _Note: When specified, this value is persisted by HolOS and need not be specified each time.
//! The expected pattern is to specify it once when booting from a USB stick, and then perform an
//! install, which will inherit this parameter and the trusted ssh keys._
//!
//! This parameter takes the form of a comma separated list of usernames, with no spaces. For
//! example:
//!
//! ```text
//! github_usernames=me,my_friend,another_friend
//! ```
//!
//! HolOS does not include _any_ keys by default and never automatically trusts keys from anyone
//! involved in any of the Holo projects.
//!
//! More information about the semantics can be found below in the `trusted-keys` subcommand to the
//! (internal) `holos-config` tool.
//!
//! ## `config_file` kernel parameter
//!
//! The `config_file` parameter primarily exists for testing, but could have some supportability
//! use cases in the future. HolOS picks a configuration file from existing local modifications,
//! hardware discovery and fallback defaults. Most users should never need to touch this. In cases
//! where it is necessary (primarily testing for now), a configuration file may be explicitly
//! specified using this parameter. For example:
//!
//! ```text
//! config_file=/etc/holos/configs/custom.yaml
//! ```
//!
//! ## `ssh_keys` kernel parameter
//!
//! If a Github account with public ssh keys is not available, it is possible to explicitly pass in
//! a set of ssh keys as strings. This is not recommended, as the default for an edge node is to
//! interact through the console (keyboard and monitor). OpenSSH public keys are quite long and
//! typing one in correctly on the kernel command line is laborious and error-prone.
//!
//! This exists as a mirror of a configuration file parameter. If explicit ssh keys are what a
//! given edge node requires, it is suggested that the Github keys be used initially to bootstrap
//! the system, and then to remove the Github usernames from the configuration file and add the
//! explicit ssh keys and reboot to enact the changes (or run `holos-config trusted-keys`).
//!
//! Alternatively, PXE booting HolOS would allow a custom bootloader configuration to be created
//! that included the static keys. PXE booting is possible, but left as an exercise to the reader
//! (or reach out).
//!
//! Finally, the hybrid ISO could be remastered to include a custom bootloader config containing
//! the `ssh_keys` kernel parameter. This is, again, left as an exercise to the reader. There are
//! certain things that need to happen for a remastered image to successfully boot and we have
//! already seen attempts at remastering the ISO using a common Windows tool, resulting in a broken
//! USB stick image.
//!
//! The command used to build the hybrid ISO, given a directory containing all of the ISO image
//! files, including any modified bootloader configuration, would need to look something like this:
//!
//! ```text
//! xorriso -as mkisofs \
//!	-r \
//!	-V HolOS-install \
//!	-o ../holos-${HOLOS_VERSION}.iso \
//!	-isohybrid-mbr ../br-build/host/share/syslinux/isohdpfx.bin \
//!	-b isolinux/isolinux.bin \
//!	-c boot/boot.cat \
//!	-no-emul-boot \
//!	-boot-load-size 4 \
//!	-boot-info-table \
//!	.
//! ```
//!
//! ## `rootpw_hash` kernel parameter
//!
//! Similar to the `ssh_keys` parameter, this is not the recommended approach and has similar
//! drawbacks to the `ssh_keys` parameter. The `rootpw_hash` parameter allows the user to specify a
//! SHA256 hashed password to set as the root password. By default, the root account is locked.
//! Setting this option, sets the root password, allowing root logins with this password on the
//! console (not over ssh).
//!
//! It is still recommended to use the Github usernames approach above for populating a list of
//! root-trusted ssh keys over using a root password. This is provided only for cases where Github
//! is not an option and has the same challenges as the `ssh_keys` parqmeter above.
//!
//! The hashed password needs to be created in a specific way. Tools such as `sha256sum` available
//! on many operating systems is _not_ sufficient. Instead, it is recommnded that a tool such as
//! `openssl` be used. To duplicate the example given in more detail below:
//!
//! ```text
//! $ openssl passwd -5 -stdin
//! <type password string here>
//! ^D
//! $5$xkiafp66GGm9of1e$vkQbuykUdRT/oEc8RqUTf4XEJwWBDnFGU2s9nrCNMyD
//! ```
//!
//!
//! # `holos-config` command line
//!
//! The `holos-config` tool is (currently) used only for internal processes within HolOS. It is
//! anticipated that there may be some user-oriented functionalites added later, but for now it's
//! all internal. That said, for clarity and for supportability, its subcommands are documented
//! below.
//!
//! ## `trusted-keys` subcommand
//! The `trusted-keys` subcommand will download public SSH keys from github for any users
//! specified, and/or include any public keys explicitly included, and have the HolOS root
//! user trust those public keys.
//!
//! The list of github users to retrieve keys for can be specified on the kernel command
//! line (via the bootloader) using the `github_usernames` command line option. It is a
//! comma-separated, with no spaces, argument. For example,
//! `github_usernames=mattgeddes,SIR-ROB,zippy`.
//!
//! It is OK to specify a username that has zero ssh keys currently, but specifying an
//! invalid github username, or if there is some other problem with retrieving keys for any
//! of the users (network connectivity, for example), this process will fail and the
//! existing trusted keys file will remain intact.
//!
//! Specific OpenSSH keys can be included as strings, where the preferred Github approach
//! is not available. This done using the `ssh_pubkeys` option, which is (again), a
//! comma-separated list of ssh public key strings. The public key string is the first two
//! columns of the key (the key type and the key content) without the third (comment)
//! column, and with the space between the columns replaced with an underscore ('_').
//!
//! For example: `ssh_pubkeys=ecdsa-sha2-nistp256_AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKPs0nv/jVhzbojZ8e3T7PmUrWNOeeL+fYzbKC6Rs8Cwuu80UMBQ75VzfPBOKsBFb98fhOzSjPkYKGKB3D5GZZ4=`
//!
//! The kernel command line parameters passed in are written to the running configuration
//! file, so do not need to be specified each boot. The expected general flow would be to:
//!  1. Boot the HolOS ISO in _install_ mode with a valid `github_usernames` parameter
//!  2. Have the HolOS configurator download the keys and trust them, granting root access
//!     to the users whose keys are trusted.
//!  3. Allow the install to proceed, including keeping the specified ssh keys configuration.
//!
//!  This is the general flow most folks will follow, but other use cases (such as selective remote
//!  support) are also possible.
//!
//!  Note that no keys are added by default, and no Holo project member keys or other default keys
//!  are ever added automatically. If no keys are specified and not root password hash is specified
//!  (see docs elsewhere), the user will have no way to log in. This can be remedied by rebooting
//!  and passing in one of the kernel parameters through the bootloader.
//!
//! ## `root-password` subcommand
//!
//! This subcommand to `holos-config` takes the user-provided root password hash and writes it to
//! the shadow password file, thereby enabling interactive logins on the console as the root user.
//! By default, the root account is locked with no valid password and cannot log in on the console.
//! The preferred method of login is to login as root using SSH and trusted public keys. For cases
//! where that is not possible, the user can SHA256-hash a string into a hashed string suitable for
//! use with the Linux authentication subsystem.
//!
//! To hash a plaintext password, the `openssl` tool available on most Linux, Unix and Mac systems,
//! and available for Windows may be used. The following command will read a password from stdin on
//! most platforms, and output a valid SHA256 hashed password string:
//!
//! ```text
//! $ openssl passwd -5 -stdin
//! <type password string here>
//! ^D
//! $5$xkiafp66GGm9of1e$vkQbuykUdRT/oEc8RqUTf4XEJwWBDnFGU2s9nrCNMyD
//! ```
//!
//! To summarise, you can run the above command, type the password in plaintext as input to the
//! `openssl` command, hit return, then `^D`, and the `openssl` command will display the SHA256
//! hashed password and return you to your shell prompt.
//!
//! This string, copied exactly, can be passed to HolOS via the kernel command line or added
//! directly to the configuration file after the fact. The kernel command line argument for passing
//! a hashed password in is `rootpw_hash`. An example using the above-hashed password might look
//! like this on the kernel command line:
//!
//! ```text
//! rootpw_hash=$5$xkiafp66GGm9of1e$vkQbuykUdRT/oEc8RqUTf4XEJwWBDnFGU2s9nrCNMyD
//! ```
//!
//! # `holos-config` environment variables
//!
//! The `holos-config` tools supports a number of environment variables. These are almost entirely
//! there for development and testing and not expected to be used in the real world. This section
//! aims to describe each:
//!
//! * `CMDLINE_PATH` -- There are various parameters that can be passed in on the Linux kernel
//! command line. This is parsed from `/proc/cmdline`, but this path can be overriden with the
//! `CMDLINE_PATH` environment variable when testing.
//! * `CONFIG_PATH` -- The directory under which `holos-config` searches for default and per-model
//! configuration files. This can be overriden with this environment variable.
//! * `LOCAL_CONFIG_FILE` -- When configuration parameters are overriden using mechanisms such as
//! the kernel command line, they are written to a new configuration file with all of the local
//! changes. This file takes precedence over other configuration files. For testing, the path where
//! this file is _written_ can be overridden using the `LOCAL_CONFIG_FILE` environment variable.
//! * `AUTHORIZED_KEYS_DIR` -- When `holos-config` writes downloaded or provided ssh public keys to
//! trust, it will write to the root user's `authorized_keys` file in the `/root/.ssh` directory.
//! The directory can be overridden with this environment variable.
//! * `INTERFACES_PATH` -- This variable allows the network configuration directory to be
//! overridden during testing, to allow the tester to write and check network interface
//! configuration files independently of HolOS.
//!

use ipnet::IpNet;
use serde_derive::{Deserialize, Serialize};
use serde_with::serde_as;
use std::net::IpAddr;

//pub mod blockdev;
//pub mod install;
pub mod models;
pub mod update;
pub mod utils;

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
    /// Update related configuration content.
    pub updates: UpdateConfig,
}

/// Configuration for data/system persistence.
#[derive(Debug, Serialize, Deserialize)]
pub struct StorageConfig {
    /// Partition to install Holos to.
    pub system_device: Option<String>,
    /// Partition to persist Holo and Holochain data to.
    pub data_device: Option<String>,
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

/// Configuration of the updates channel
#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateConfig {
    /// URL to pull from. Should generally always be a `channels.yaml` file in Github release page
    /// for Holo Edgenode.
    channel_url: String,
    /// The name of the channel to update through. Will generally be _release_.
    channel_name: String,
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
        /// This is to pass in specific ssh keys, rather than pull from github.
        pub ssh_pubkeys: Vec<String>,
        /// This gives the user a way to pass in a root password hash to add to the shadow file,
        /// should the user want to enable interactive logins for root on the console.
        pub rootpw_hash: String,
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
            let mut ssh_pubkeys: Vec<String> = vec![];
            let mut rootpw_hash = String::new();
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
                    } else if let Some(pubkey) = arg.strip_prefix("ssh_keys=") {
                        // We expect this string to be of the format:
                        //   ssh_keys=<type>_<pubkey>,<type>_<pubkey>
                        // Where 'type' is the key type (eg ecdsa-sha2-nistp256) and 'pubkey' is
                        // the public key string, minus the comment field.
                        ssh_pubkeys = pubkey
                            .split(',')
                            .map(|s| s.to_string().replace('_', " "))
                            .collect();
                    } else if let Some(rootpw) = arg.strip_prefix("rootpw_hash=") {
                        // This is expected to be a sha256-encoded hash of the root password we
                        // want to set.
                        rootpw_hash = rootpw.to_string();
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
                ssh_pubkeys,
                rootpw_hash,
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
