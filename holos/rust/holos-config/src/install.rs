/// HolOS installer.
/// This will gather information that's discovered and specified and create an installation plan
/// from there. The installation plan is then used to apply the operating system to disk and make
/// it bootable. We create (if necessary), *two* partitions/filesystems for the operating system --
/// one labelled 'flip' and one labelled 'flop'. This will (in future) allow us to manage updates
/// and rollbacks by writing to one or the other and switching which one will be booted by default.
///
/// We keep the application data (including container images) separate in order to avoid touching
/// the data on upgrades or reinstalls. But also to have the application data (presumably our
/// primary source of random I/O) on the SSDs of the holoport plus.
use crate::{HolosConfig, models::Model};
use anyhow::{Error, anyhow};
use console::Style;
use dialoguer::{Confirm, Input, Select, theme::ColorfulTheme};
use glob::glob;
use libblkid_rs::BlkidProbe;
use log::{debug, info};
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug)]
pub struct Installer {
    install_plan: InstallationPlan,
}
#[derive(Debug)]
pub struct InstallationPlan {
    /// Currently a string containing the device node of the volume containing the source media.
    /// Will (soon?) support other sources, such as HTTPS.
    source_media: String,
    /// A list of block devices we plan to wipe and repartition.
    filesystem_layouts: HashMap<String, Vec<FilesystemDefinition>>,
}

impl InstallationPlan {
    pub fn apply(&self) -> Result<(), Error> {
        info!("Mount source media from {}", self.source_media);

        info!("Create necessary filesystems:");
        for block_device in self.filesystem_layouts.keys() {
            info!("  - {}", block_device);
            for partition in &self.filesystem_layouts[block_device] {
                info!(
                    "    * '{}' {} {}",
                    partition.label, partition.fstype, partition.size
                );
            }
        }
        Ok(())
    }
}

#[derive(Debug)]
pub struct FilesystemDefinition {
    /// The filesystem label to assign. The partitioning and formatting stuff is the only place
    /// where we should be dealing with block device names. We use labels for everything else,
    /// including mounting.
    label: String,
    /// The filesystem type to create the filesystem as when we create it (usually ext4, but could
    /// well be others in the future.
    fstype: String,
    /// A parted-compatible size string for the partition.
    size: String,
}

impl Installer {
    const SOURCE_FS_LABEL_NAME: &str = "HolOS-install";
    const SYSTEM_FLIP_LABEL_NAME: &str = "HolOS-sys-flip";
    const SYSTEM_FLOP_LABEL_NAME: &str = "HolOS-sys-flop";
    const DATA_FS_LABEL_NAME: &str = "HolOS-data";

    const BLOCKDEV_PARTITION_GLOB: &str = "/sys/class/block/*/partition";

    // Installer:
    //  - If we have existing volume for each data set, suggest we use those
    //  - If not, ask for a destination device to create volumes on
    //      - then partition
    pub fn do_install(config: &HolosConfig, model: &Model) -> Result<(), Error> {
        let theme = ColorfulTheme {
            values_style: Style::new().yellow().dim(),
            ..ColorfulTheme::default()
        };

        let fs_hints = Self::blockdev_hints();
        dbg!(&fs_hints);

        // TODO: tidy the summary output up
        println!("HolOS Installer");
        println!("---------------\n");
        println!(
            "Using default install parameters for platform model '{}':",
            model
        );
        if fs_hints.contains_key(Self::SOURCE_FS_LABEL_NAME) {
            println!(
                "Found source media on device {}",
                fs_hints[Self::SOURCE_FS_LABEL_NAME]
            );
        }
        if fs_hints.contains_key(Self::DATA_FS_LABEL_NAME) {
            println!(
                "Found existing application data on device {}",
                fs_hints[Self::DATA_FS_LABEL_NAME]
            );
        }
        if fs_hints.contains_key(Self::SYSTEM_FLIP_LABEL_NAME) {
            println!(
                "Found system primary on device {}",
                fs_hints[Self::SYSTEM_FLIP_LABEL_NAME]
            );
        }
        if fs_hints.contains_key(Self::SYSTEM_FLOP_LABEL_NAME) {
            println!(
                "Found system secondary on device {}",
                fs_hints[Self::SYSTEM_FLOP_LABEL_NAME]
            );
        }

        Ok(())
    }

    fn blockdev_hints() -> HashMap<String, String> {
        let mut ret = HashMap::new();

        match glob(Self::BLOCKDEV_PARTITION_GLOB) {
            Ok(part_devs) => {
                for part in part_devs {
                    let mut path = match part {
                        Ok(p) => p,
                        Err(_) => {
                            continue;
                        }
                    };
                    path.pop();

                    if let Some(dev) = path.file_name() {
                        debug!("Scanning partition: /dev/{}", dev.to_string_lossy());
                        let dev_path = format!("/dev/{}", dev.to_string_lossy());
                        match Self::get_fs_label(&dev_path) {
                            Ok(label) => {
                                // do things
                                match label.as_str() {
                                    Self::DATA_FS_LABEL_NAME => {
                                        ret.insert(Self::DATA_FS_LABEL_NAME.to_string(), dev_path)
                                    }
                                    Self::SYSTEM_FLIP_LABEL_NAME => ret
                                        .insert(Self::SYSTEM_FLIP_LABEL_NAME.to_string(), dev_path),
                                    Self::SYSTEM_FLOP_LABEL_NAME => ret
                                        .insert(Self::SYSTEM_FLOP_LABEL_NAME.to_string(), dev_path),
                                    Self::SOURCE_FS_LABEL_NAME => {
                                        ret.insert(Self::SOURCE_FS_LABEL_NAME.to_string(), dev_path)
                                    }
                                    _ => {
                                        continue;
                                    }
                                };
                            }
                            Err(_) => {
                                continue;
                            }
                        }
                    }
                }
            }
            Err(_) => return ret,
        };
        ret
    }

    fn get_fs_label(path: &str) -> Result<String, Error> {
        let mut probe = BlkidProbe::new_from_filename(Path::new(path))?;
        probe.enable_superblocks(true)?;
        probe.enable_partitions(true)?;
        probe.do_safeprobe()?;

        let probed_label = probe.lookup_value("LABEL");
        if let Ok(lbl) = probed_label {
            debug!("Found FS label {} on {}", lbl, path);
            return Ok(lbl);
        }

        Err(anyhow!("Label not found"))
    }
}
