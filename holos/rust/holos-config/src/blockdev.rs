use glob::glob;
use libblkid_rs::BlkidProbe;
use log::info;
use std::error::Error;
use std::path::Path;

#[derive(Debug)]
pub struct BlockDev {
    pub dev_node: String,
    pub label: String,
    pub removable: bool,
    pub rotational: bool,
}

impl BlockDev {
    /// This constant represents the file glob pattern we use to discover all partitions on all
    /// block devices currently attached to the system.
    const BLOCKDEV_PARTITION_GLOB: &str = "/sys/class/block/*/partition";

    pub fn probe_blockdevs() -> Result<Option<Vec<BlockDev>>, Box<dyn Error>> {
        let mut ret = vec![];

        for path in glob(BlockDev::BLOCKDEV_PARTITION_GLOB)? {
            let mut path = path?;
            // Remove the `/partition` portion of the path.
            path.pop();
            // We want the block device name in order to probe it
            if let Some(dev) = path.file_name() {
                info!("Scanning partition: /dev/{}", dev.to_string_lossy());
                let dev_path = format!("/dev/{}", dev.to_string_lossy());
                ret.push(BlockDev::probe_blockdev(&dev_path)?);
            }
        }

        Ok(Some(ret))
    }
    pub fn probe_blockdev(path: &str) -> Result<BlockDev, Box<dyn Error>> {
        let mut probe = BlkidProbe::new_from_filename(Path::new(&path))?;
        probe.enable_superblocks(true)?;
        probe.enable_partitions(true)?;
        probe.do_safeprobe()?;

        let mut label = "".to_string();
        let probed_label = probe.lookup_value("LABEL");
        if let Ok(lbl) = probed_label {
            info!("Found FS label {} on device {}", lbl, path);
            label = lbl;
        }

        let dev_node = path.to_string();

        Ok(BlockDev {
            dev_node,
            label,
            rotational: false, //TODO
            removable: false,  // TODO
        })
    }
}
