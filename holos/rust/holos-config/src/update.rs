use crate::UpdateConfig;
use anyhow::{Error, anyhow};
use log::info;
use reqwest::{Client, StatusCode};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::env;
use std::fs::{self, File};
use std::io::Write;
use std::process::Command;

/// A list of named channels published online somewhere.
pub struct UpdateChannelsList(HashMap<String, UpdateChannel>);

impl UpdateChannelsList {
    pub async fn new(channel_url: &str) -> Result<Self, Error> {
        let client = Client::new();
        let response = client
            .get(channel_url)
            .header("User-Agent", "HolOS Configurator")
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            return Err(anyhow!(
                "Failed to fetch update channels from '{channel_url}': HTTP {status}"
            ));
        }

        let response_body = response.text().await.map_err(|e| {
            anyhow!("Failed to read update channels response from '{channel_url}': {e}")
        })?;

        let channels: HashMap<String, UpdateChannel> = serde_yaml::from_str(&response_body)
            .map_err(|e| {
                anyhow!("Failed to parse update channels YAML from '{channel_url}': {e}")
            })?;
        Ok(Self(channels))
    }
    pub fn channel_by_name(&self, name: &str) -> Option<&UpdateChannel> {
        info!("Channel {}: {:?}", name, self.0.get(name));
        self.0.get(name)
    }
}
#[derive(Debug, Deserialize)]
pub struct UpdateChannel {
    /// The version of HolOS. 0.0.8, for example. Could be converted to a semver struct later if
    /// necessary.
    pub version: String,
    /// The URL to retrieve the source media from.
    pub media_url: String,
    /// The URL to retrieve the version release notes from.
    pub release_notes_url: String,
    /// Whether this version is for public consumption or not.
    pub generally_available: bool,
    /// A string representing the release date. Could be parsed into an RFC-3341 compatible struct
    /// if necessary.
    pub date_released: String,
    /// Container images and versions to pull that are preferred with this version of HolOS.
    pub container_images: Vec<ContainerImage>,
}

#[derive(Debug, Deserialize)]
pub struct ContainerImage {
    pub name: String,
    pub tag: String,
}

pub struct Updater {}

impl Updater {
    const DOWNLOAD_DIRECTORY: &str = "/var/tmp";
    const HOLOS_VERSION_FILE: &str = "/etc/holos-version";

    pub async fn do_update(config: &UpdateConfig) -> Result<(), Error> {
        //  - Mount destination (flip or flop)
        //  - Extract the root filesystem to flip or flop
        //  - Update bootloader
        //  - Pull docker images
        //  - reboot
        info!("Updating through channel {}", config.channel_name);
        let channels = UpdateChannelsList::new(&config.channel_url).await?;
        if let Some(mychan) = channels.channel_by_name(&config.channel_name) {
            // Is an update required?
            let version_file = fs::read_to_string(Self::HOLOS_VERSION_FILE)?;
            let current_version = version_file.trim();
            if mychan.version == current_version {
                info!(
                    "Already running version {}. No update required.",
                    mychan.version
                );
                return Ok(());
            }

            let destination_file = match env::var("DOWNLOAD_DIRECTORY") {
                Ok(dir) => format!("{}/update.iso", dir),
                Err(_) => format!("{}/update.iso", Self::DOWNLOAD_DIRECTORY),
            };
            // Download the specified version ISO
            let client = Client::new();
            let mut response = client.get(&mychan.media_url).send().await?;

            let media_hash_string = match response.status() {
                StatusCode::OK => {
                    // As we download and write the file, calculate its SHA256 hash, so that we can check
                    // it once it's done.
                    let mut hasher = Sha256::new();

                    let mut dest_file = File::create(&destination_file)?;
                    while let Some(chunk) = response.chunk().await? {
                        hasher.update(&chunk);
                        dest_file.write_all(&chunk)?;

                    }

                    let hash_bytes = hasher.finalize();
                    let hash_string = format!("{:x}", hash_bytes);
                    hash_string
                }
                status => {
                    info!("Download of {} failed with {}", mychan.media_url, status);
                    return Err(anyhow!(format!(
                        "Update download failed with HTTP {}",
                        status
                    )));
                }
            };

            info!(
                "SHA256 hash of downloaded media file was: {}",
                media_hash_string
            );

            // Now retrieve the published SHA256 hash, so that we can compare the two.
            let hash_file_content = client
                .get(format!("{}.sha256", &mychan.media_url))
                .send()
                .await?
                .text()
                .await?;
            let published_hash_string = hash_file_content.trim_end();

            if media_hash_string != published_hash_string {
                return Err(anyhow!(
                    "Hash check for {} failed. Expected {}, but got {}.",
                    &mychan.media_url,
                    published_hash_string,
                    media_hash_string
                ));
            }

            info!("SHA256 hash check for {} succeeded.", mychan.media_url);

            // Trading off time vs resilience, much of the update mechanism has been implemented
            // as a shell script.
            let output = Command::new("/bin/update-extractor.sh")
                .arg(&destination_file)
                .arg("/flipflop")
                .output()?;

            info!("Update stdout: {}", &str::from_utf8(&output.stdout)?);
            info!("Update stderr: {}", &str::from_utf8(&output.stderr)?);

            // TODO: Automatically reboot here?

            return Ok(());
        } else {
             Err(anyhow!(
                "Channel '{}' not found in update channels list",
                config.channel_name
            ))

    }
}
}
