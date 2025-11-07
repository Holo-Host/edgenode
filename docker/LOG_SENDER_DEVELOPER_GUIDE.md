# `log-sender` User Guide

This document provides a comprehensive overview of the `log-sender` utility, including its source code, configuration, dependencies, and usage.

## Main Source Code (`src/bin/log-sender.rs`)

```rust
#[derive(Debug, clap::Parser)]
#[command(version, about)]
struct Arg {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Debug, clap::Subcommand)]
enum Cmd {
    /// Initialize a new config file. Note, this will generate a new
    /// drone cryptographic keypair, register it with the provided
    /// endpoint server, and write out a config file for operations.
    Init {
        /// Specify a full path to a config file,
        /// e.g. `/var/run/log-sender-runtime.json`.
        #[arg(long, env = "LOG_SENDER_CONFIG_FILE")]
        config_file: std::path::PathBuf,

        /// Specify the endpoint url of the log-collector endpoint,
        /// e.g. `https://log-collector.my.url`.
        #[arg(long, env = "LOG_SENDER_ENDPOINT")]
        endpoint: String,

        /// Base64 Unyt Public Key for registration.
        #[arg(long, env = "LOG_SENDER_UNYT_PUB_KEY")]
        unyt_pub_key: String,

        /// Frequency at which to run reporting.
        #[arg(long, env = "LOG_SENDER_REPORT_INTERVAL_SECONDS")]
        report_interval_seconds: u64,

        /// Specify one or more paths to directories that will contain log files
        /// with entries to be published as log-collector metrics. The sender
        /// will parse all files ending in a `.jsonl` extension. Specify
        /// this argument multiple times on the command line, or if using
        /// an environment variable, separate the paths with commas.
        #[arg(long, env = "LOG_SENDER_REPORT_PATHS", value_delimiter = ',')]
        report_path: Vec<std::path::PathBuf>,

        /// Specify one or more conductor config paths. These will be used
        /// to report on database sizes on-disk at the reporting interval.
        /// Specify this argument multiple times on the command line, or if
        /// using an environment variable, separate the paths with commas.
        #[arg(
            long,
            env = "LOG_SENDER_CONDUCTOR_CONFIG_PATHS",
            value_delimiter = ','
        )]
        conductor_config_path: Vec<std::path::PathBuf>,
    },

    /// Run the service, polling a log-file directory for metrics to
    /// publish to the log-collector.
    Service {
        /// Specify a full path to a config file,
        /// e.g. `/var/run/log-sender-runtime.json`.
        #[arg(long, env = "LOG_SENDER_CONFIG_FILE")]
        config_file: std::path::PathBuf,
    },
}

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    tracing::subscriber::set_global_default(
        tracing_subscriber::FmtSubscriber::builder()
            .with_env_filter(
                tracing_subscriber::EnvFilter::builder()
                    .with_default_directive(
                        tracing_subscriber::filter::LevelFilter::INFO.into(),
                    )
                    .from_env_lossy(),
            )
            .compact()
            .without_time()
            .finish(),
    )
    .unwrap();

    let arg: Arg = clap::Parser::parse();

    tracing::info!(cmd = ?arg.cmd, "Running Command");

    match arg.cmd {
        Cmd::Init {
            config_file,
            endpoint,
            unyt_pub_key,
            report_interval_seconds,
            report_path,
            conductor_config_path,
        } => log_sender::initialize(
            config_file,
            endpoint,
            unyt_pub_key,
            report_interval_seconds,
            report_path,
            conductor_config_path,
        )
        .await
        .unwrap(),
        Cmd::Service { config_file } => {
            log_sender::run_service(config_file).await.unwrap()
        }
    }
}
```

## Configuration (`src/config.rs`)

```rust
//! Configuration types.

use super::*;

/// Runtime configuration.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeConfig {
    /// Log collector endpoint.
    pub endpoint: String,

    /// Drone public key.
    pub drone_pub_key: String,

    /// Drone secret key.
    pub drone_sec_key: String,

    /// Unyt public key.
    pub unyt_pub_key: String,

    /// Drone id.
    pub drone_id: u64,

    /// Report interval seconds.
    pub report_interval_seconds: u64,

    /// List of paths from which to pull reports.
    pub report_path_list: Vec<std::path::PathBuf>,

    /// List of conductor config paths, for pulling db size reports.
    pub conductor_config_path_list: Vec<std::path::PathBuf>,

    /// Last record timestamp sent.
    pub last_record_timestamp: String,
}

impl RuntimeConfig {
    /// Create a new runtime configuration instance.
    #[allow(clippy::too_many_arguments)]
    pub fn with_init(
        endpoint: String,
        drone_pub_key: String,
        drone_sec_key: String,
        unyt_pub_key: String,
        drone_id: u64,
        report_interval_seconds: u64,
        report_path_list: Vec<std::path::PathBuf>,
        conductor_config_path_list: Vec<std::path::PathBuf>,
    ) -> Self {
        Self {
            endpoint,
            drone_pub_key,
            drone_sec_key,
            unyt_pub_key,
            drone_id,
            report_interval_seconds,
            report_path_list,
            conductor_config_path_list,
            last_record_timestamp: "0".into(),
        }
    }
}

/// Runtime configuration file with advisory locking.
pub struct RuntimeConfigFile {
    config: RuntimeConfig,
    file: tokio::fs::File,
    path: std::path::PathBuf,
    pub(crate) rt_drone_sec_key: SecKey,
}

impl From<RuntimeConfigFile> for RuntimeConfig {
    fn from(config: RuntimeConfigFile) -> Self {
        config.config
    }
}

impl std::ops::Deref for RuntimeConfigFile {
    type Target = RuntimeConfig;

    fn deref(&self) -> &Self::Target {
        &self.config
    }
}

impl std::ops::DerefMut for RuntimeConfigFile {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.config
    }
}

impl RuntimeConfigFile {
    /// Initialize a new config file.
    pub async fn with_init(
        file: std::path::PathBuf,
        endpoint: String,
        unyt_pub_key: String,
        drone_id: u64,
        report_interval_seconds: u64,
        report_path_list: Vec<std::path::PathBuf>,
        conductor_config_path_list: Vec<std::path::PathBuf>,
    ) -> Result<Self> {
        let (rt_drone_pub_key, mut rt_drone_sec_key) =
            generate_keypair().await?;
        rt_drone_sec_key = rt_drone_sec_key.precompute().await?;

        let path = file.clone();
        let file = tokio::task::spawn_blocking(move || {
            use fs2::FileExt;
            let file = std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create_new(true)
                .open(file)?;
            file.try_lock_exclusive()?;
            std::io::Result::Ok(tokio::fs::File::from_std(file))
        })
        .await??;

        let config = RuntimeConfig::with_init(
            endpoint,
            rt_drone_pub_key.encode()?,
            rt_drone_sec_key.encode()?,
            unyt_pub_key,
            drone_id,
            report_interval_seconds,
            report_path_list,
            conductor_config_path_list,
        );

        let mut this = Self {
            config,
            file,
            path,
            rt_drone_sec_key,
        };

        this.write().await?;

        Ok(this)
    }

    /// Load a runtime config from disk.
    pub async fn with_load(file: std::path::PathBuf) -> Result<Self> {
        use tokio::io::AsyncReadExt;

        let path = file.clone();

        let mut file = tokio::task::spawn_blocking(move || {
            use fs2::FileExt;
            let file = std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(file)?;
            file.try_lock_exclusive()?;
            std::io::Result::Ok(tokio::fs::File::from_std(file))
        })
        .await??;

        let mut config = String::new();
        file.read_to_string(&mut config).await?;
        let config: RuntimeConfig = serde_json::from_str(&config)?;

        let mut rt_drone_sec_key =
            SecKey::decode(config.drone_sec_key.as_bytes())?;
        rt_drone_sec_key = rt_drone_sec_key.precompute().await?;

        Ok(Self {
            config,
            file,
            path,
            rt_drone_sec_key,
        })
    }

    /// Get the path of the file on-disk.
    pub fn path(&self) -> &std::path::Path {
        &self.path
    }

    /// Write the config to the file.
    pub async fn write(&mut self) -> Result<()> {
        use tokio::io::{AsyncSeekExt, AsyncWriteExt};
        let data = serde_json::to_string_pretty(&self.config)?;
        self.file.rewind().await?;
        self.file.set_len(data.len() as u64).await?;
        self.file.write_all(data.as_bytes()).await?;
        self.file.flush().await?;
        Ok(())
    }
}
```

## Dependencies (`Cargo.toml`)

```toml
[package]
name = "log-sender"
version = "0.1.3"
edition = "2024"

[dependencies]
base64 = "0.22.1"
clap = { version = "4.5.47", features = ["derive", "env", "wrap_help"] }
fs2 = "0.4.3"
rand = "0.8"
reqwest = { version = "0.12.23", default-features = false, features = ["json", "native-tls-vendored"] }
rsa = { version = "0.9.8", features = ["sha2"] }
serde = { version = "1.0.219", features = ["derive"] }
serde_json = { version = "1.0.143", features = ["preserve_order"] }
serde_yaml = "0.9.34"
tokio = { version = "1.47.1", features = ["full"] }
tracing = "0.1.41"
tracing-subscriber = { version = "0.3.20", features = ["env-filter"] }

[dev-dependencies]
tempfile = "3.22.0"
tracing-appender = "0.2.3"
```

## Usage and Command-Line Arguments

The `log-sender` utility has two main subcommands: `init` and `service`.

**`init`**

Initializes a new configuration file. This command generates a new drone cryptographic keypair, registers it with the provided endpoint server, and writes out a config file for operations.

*   `--config-file`: Specify a full path to a config file, e.g. `/var/run/log-sender-runtime.json`. (Env: `LOG_SENDER_CONFIG_FILE`)
*   `--endpoint`: Specify the endpoint url of the log-collector endpoint, e.g. `https://log-collector.my.url`. (Env: `LOG_SENDER_ENDPOINT`)
*   `--unyt-pub-key`: Base64 Unyt Public Key for registration. (Env: `LOG_SENDER_UNYT_PUB_KEY`)
*   `--report-interval-seconds`: Frequency at which to run reporting. (Env: `LOG_SENDER_REPORT_INTERVAL_SECONDS`)
*   `--report-path`: Specify one or more paths to directories that will contain log files with entries to be published as log-collector metrics. The sender will parse all files ending in a `.jsonl` extension. (Env: `LOG_SENDER_REPORT_PATHS`)
*   `--conductor-config-path`: Specify one or more conductor config paths. These will be used to report on database sizes on-disk at the reporting interval. (Env: `LOG_SENDER_CONDUCTOR_CONFIG_PATHS`)

**`service`**

Runs the service, polling a log-file directory for metrics to publish to the log-collector.

*   `--config-file`: Specify a full path to a config file, e.g. `/var/run/log-sender-runtime.json`. (Env: `LOG_SENDER_CONFIG_FILE`)

## Directory Structure

.
├── .github
├── .gitignore
├── .rustfmt.toml
├── Cargo.lock
├── Cargo.toml
├── E2E.md
├── examples
│   └── test-writer.rs
├── LOG_SENDER_USER_GUIDE.md
├── Makefile
├── README.md
├── rust-toolchain.toml
└── src
    ├── bin
    │   └── log-sender.rs
    ├── client.rs
    ├── config.rs
    ├── crypto.rs
    ├── db_size.rs
    ├── lib.rs
    ├── reader.rs
    └── test.rs