/// This module uses some basic/crude heuristics to try and determine the model of machine we're
/// running on, to provide a potential default configuration file.
use anyhow::Error;
use bitmask_enum::bitmask;
use glob::glob;
use log::info;
use std::fmt;
use std::fs;
//use std::path::Path;

pub struct ModelConfig {}

impl ModelConfig {
    pub fn config_file() -> Option<String> {
        Some("/etc/holos/configs/default.yaml".to_string())
    }
}

#[bitmask(u32)]
enum ModelHeuristicFlags {
    Empty = 0,
    /// This indicates that the device has the USB-serial device that holoport LEDs are attached
    /// to.
    HasHoloportLED,
    /// This currently only looks for a rotational, non-removable drive, but later, ought to
    /// look for that on a specific SATA slot.
    HasHoloportHDD,
    /// This currently only looks for a non-rotational, non-removable drive, but later, ought to
    /// look for that on a specific SATA slot.
    HasHoloportPlusSSD,
    /// Looks for a Dell USB fingerprint reader. For no reason other than it's a fairly unique USB
    /// device to some hardware I'm testing against.
    HasDellXpsFPR,
    /// Checks against the DMI/SMI ID data.
    HasDellXpsSMI,
    /// Looks for a drive on a virtio bus.
    HasVirtIODrive,
}

#[derive(Debug)]
pub enum Model {
    Unknown,
    /// Original Holoport
    Holoport,
    /// Holoport with an added SSD and a larger HDD
    HoloportPlus,
    /// A specific configuration of a QEMU/VirtIO/KVM VM used in testing.
    VirtioVM,
    /// Matt's laptop, also used for testing.
    DellXPS13,
}

impl fmt::Display for Model {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let ret = match self {
            Self::Unknown => "Unknown Model",
            Self::Holoport => "Holoport",
            Self::HoloportPlus => "Holoport Plus",
            Self::VirtioVM => "VM with VirtIO",
            Self::DellXPS13 => "Dell XPS 13 9310",
        };

        write!(f, "{}", ret)
    }
}

impl Model {
    /// String to glob all USB devices by modalias. This allows us to find hardware devices by
    /// vendor/product ID with a simple string comparison, and use that to identify unique devices,
    /// such as the USB LED device present in the holoports.
    const USB_MODALIAS_GLOB: &str = "/sys/bus/usb/devices/*/modalias";
    /// Block devices that are backed by hardware (this excludes things like partitions and
    /// loopback block devices) generally represent entire physical devices, such as SSDs and
    /// spinning rust drives. This glob should narrow things down to those for us to poke and prod
    /// at.
    const BLOCKDEV_HARDWARE_GLOB: &str = "/sys/class/block/*/device";

    /// Holoports don't have any of the SMI/DMI data that identifies models etc. So we need to
    /// offer a sacrifice to the hardware gods, in the form of poking and prodding around the
    /// hardware for something that looks approximately like something. Nothing we do is *really*
    /// tied heavily to the hardware, but a few hints can help us to provide the user with some
    /// good defaults.
    pub fn detect_model() -> Result<Self, Error> {
        let mut found_flags: ModelHeuristicFlags = ModelHeuristicFlags::Empty;

        // Scan the USB bus for largely-unique devices.
        for dev in glob(Self::USB_MODALIAS_GLOB)? {
            let dev = dev?;
            if let Some(modalias) = Self::string_attr(format!("{}", dev.display())) {
                if modalias.starts_with("usb:v27C6p533Cd") {
                    // This exists in the Dell XPS-13 and gives me a device to test this code path
                    // against on my laptop. Otherwise, entirely useless. :)
                    found_flags = found_flags | ModelHeuristicFlags::HasDellXpsFPR;
                } else if modalias.starts_with("usb:v1A86p7523d") {
                    // This is the USB-attached LED present in holoports
                    info!(
                        "Found USB device matching holoport LED at {}",
                        dev.display()
                    );
                    found_flags = found_flags | ModelHeuristicFlags::HasHoloportLED;
                }
            }
        }

        // Take a look at block devices -- holoport vs holoport plus only seems to be
        // differentiated by a larger rotational drive and an additional SSD. Previous code used
        // specific model names to identify drives, but that doesn't necessarily work when drives
        // are replaced and largely doesn't matter to the code.
        for dev in glob(Self::BLOCKDEV_HARDWARE_GLOB)? {
            let mut dev = dev?;
            let is_rotational: bool;
            let is_removable: bool;

            // we don't need the `/device` node on the end of the path. That's just a way to glob
            // out anything we don't care about.
            dev.pop();

            // Is it a rotational drive or SSD?
            if let Some(rotational) =
                Self::integer_attr(format!("{}/queue/rotational", dev.display()))
            {
                info!("Rotational: {}", rotational);
                if rotational == 1 {
                    is_rotational = true;
                } else {
                    is_rotational = false;
                }
            } else {
                // semi-sane default
                is_rotational = false;
            }

            // Is it a removable drive?
            if let Some(removable) = Self::integer_attr(format!("{}/removable", dev.display())) {
                info!("Removable: {}", removable);
                if removable == 1 {
                    is_removable = true;
                } else {
                    is_removable = false;
                }
            } else {
                // semi-sane default
                is_removable = true;
            }

            info!(
                "Looking at block device: {} {} {}",
                dev.display(),
                is_removable,
                is_rotational
            );

            // TODO: it would be good to be able to look for more than one rotational and one
            // non-rotational drive to match holoport and holoport plus. However, using the drive
            // model string or size isn't guaranteed to be correct -- vendors often switch models,
            // plus if a drive fails and we replace it with a similar drive, the software doesn't
            // care. We likely want to keep that flexibility. We also look for the ch341 device for
            // the LED as another indication of a holoport or plus, so what we have here may
            // suffice for now. It might be better to see that they're plugged into a specific
            // model of SATA controller that matches the holoports, but probably not critical for
            // right now.
            if is_rotational && !is_removable {
                found_flags = found_flags | ModelHeuristicFlags::HasHoloportHDD;
            } else if !is_rotational && !is_removable {
                found_flags = found_flags | ModelHeuristicFlags::HasHoloportPlusSSD;
            }

            // This is to detect KVM VMs -- primary for internal testing.
            if let Some(device_name) = dev.file_name() {
                let device_name = device_name.to_string_lossy();
                if device_name.starts_with("vd") {
                    found_flags = found_flags | ModelHeuristicFlags::HasVirtIODrive;
                }
            }
        }
        // Some static identification heuristics.
        if let Some(product_name) = Self::string_attr("/sys/class/dmi/id/product_name".to_string())
        {
            // Specific to the Dell I'm testing on. Other models with SMI/DMI data could be added
            // here too.
            if product_name == "XPS 13 9310" {
                found_flags = found_flags | ModelHeuristicFlags::HasDellXpsSMI;
            }
        }

        info!("Flags of found stuff be: 0x{:02x}", found_flags);
        info!(
            "Masked be: 0x{:02x}",
            found_flags & ModelHeuristicFlags::HasVirtIODrive
        );
        // A match statement would be more rusty than this if block, but the bitwise operation on
        // the bitmask enum doesn't seem to work...
        let model = if found_flags
            == ModelHeuristicFlags::HasDellXpsSMI | ModelHeuristicFlags::HasDellXpsFPR
        {
            Model::DellXPS13
        } else if found_flags
            == ModelHeuristicFlags::HasHoloportPlusSSD
                | ModelHeuristicFlags::HasHoloportLED
                | ModelHeuristicFlags::HasHoloportHDD
        {
            Model::HoloportPlus
        } else if found_flags
            == ModelHeuristicFlags::HasHoloportLED | ModelHeuristicFlags::HasHoloportHDD
        {
            Model::Holoport
        } else if found_flags & ModelHeuristicFlags::HasVirtIODrive != ModelHeuristicFlags::Empty {
            Model::VirtioVM
        } else {
            Model::Unknown
        };
        log::info!("Detected model: {}", model);
        Ok(model)
    }

    /// Reads a sysfs file into a string.
    fn string_attr(filename: String) -> Option<String> {
        let ret = match fs::read_to_string(filename.clone()) {
            Ok(v) => v.strip_suffix("\n").unwrap_or_default().to_string(),
            Err(e) => {
                info!("Failed to read {} to a string: {}", &filename, e);
                return None;
            }
        };

        Some(ret)
    }

    /// Reads a sysfs file as an integer.
    fn integer_attr(filename: String) -> Option<u64> {
        if let Some(ret) = Self::string_attr(filename.clone()) {
            let num_ret: Option<u64> = match ret.parse() {
                Ok(v) => Some(v),
                Err(e) => {
                    info!(
                        "Failed to convert {} contents ({}) into int: {}",
                        &filename, ret, e
                    );
                    None
                }
            };
            return num_ret;
        }
        None
    }
}
