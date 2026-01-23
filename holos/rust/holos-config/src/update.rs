use crate::UpdateConfig;
use anyhow::{Error, anyhow};
use log::debug;
use reqwest::Client;
use serde::Deserialize;
use std::collections::HashMap;

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
    pub async fn do_update(config: &UpdateConfig) -> Result<(), Error> {
        // Update process:
        //  - Download channels list
        //  - Match the channel we're supposed to be downloading from
        //  - Pull the configured image object
        //  - Mount destination (flip or flop)
        //  - Extract the root filesystem to flip or flop
        //  - Update bootloader
        //  - Pull docker images
        //  - reboot
        let channels = UpdateChannelsList::new(config.channel_url()).await?;
        if let Some(mychan) = channels.channel_by_name(config.channel_name()) {
            debug!("{mychan:?}");
            return Ok(());
        }
        let channel_name = config.channel_name();
        Err(anyhow!(
            "Channel '{channel_name}' not found in update channels list"
        ))
    }
}
