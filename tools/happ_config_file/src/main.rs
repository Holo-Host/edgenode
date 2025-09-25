use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use holo_hash::{ActionHash, ActionHashB64, AgentPubKey, AgentPubKeyB64};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use std::fs;
use std::path::PathBuf;
use url::Url;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigFile {
    app: App,
    env: Env,
    #[serde(skip_serializing_if = "Option::is_none")]
    economics: Option<Economics>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct App {
    name: String,
    version: String,
    happ_url: String,
    modifiers: Modifiers,
    #[serde(rename = "init_zome_calls")]
    #[serde(skip_serializing_if = "Option::is_none")]
    init_zome_calls: Option<Vec<InitZomeCall>>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct InitZomeCall {
    #[serde(rename = "fn_name")]
    fn_name: String,
    payload: JsonValue,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Modifiers {
    network_seed: String,
    properties: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Env {
    holochain: Holochain,
    #[serde(skip_serializing_if = "Option::is_none")]
    gw: Option<Gateway>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Holochain {
    version: String,
    flags: Vec<String>,
    bootstrap_url: String,
    signal_server_url: String,
    stun_server_urls: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Gateway {
    enable: bool,
    allowed_fns: Vec<String>,
    dns_props: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Economics {
    payor_unyt_agent_pub_key: String,
    agreement_hash: String,
    price_sheet: String,
}

impl ConfigFile {
    fn validate(&self) -> Result<()> {
        // app.name: non-empty, lowercase letters, numbers, underscore
        let name_re = Regex::new(r"^[a-z0-9_]+$").unwrap();
        if self.app.name.is_empty() || !name_re.is_match(&self.app.name) {
            bail!("app.name must be lowercase alphanumeric with underscores");
        }

        // app.version: semver-ish (simple)ActionHash::try_from("uhCkkWCsAgoKkkfwyJAglj30xX_GLLV-3BXuFy436a2SqpcEwyBzm").unwrap().into(),
        let version_re = Regex::new(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$").unwrap();
        if self.app.version.is_empty() || !version_re.is_match(&self.app.version) {
            bail!("app.version must be semantic version like 0.1.0");
        }

        // app.happUrl: valid URL
        Url::parse(&self.app.happ_url).context("app.happUrl must be a valid URL")?;

        // modifiers.networkSeed: any string is allowed, including empty; no validation

        // env.holochain URLs if provided
        if !self.env.holochain.bootstrap_url.is_empty() {
            Url::parse(&self.env.holochain.bootstrap_url)
                .context("env.holochain.bootstrapUrl must be a valid URL")?;
        }
        if !self.env.holochain.signal_server_url.is_empty() {
            Url::parse(&self.env.holochain.signal_server_url)
                .context("env.holochain.signalServerUrl must be a valid URL")?;
        }
        for s in &self.env.holochain.stun_server_urls {
            if !s.is_empty() {
                Url::parse(s).context("env.holochain.stunServerUrls must contain valid URLs")?;
            }
        }
        // Optional gw validation hook
        if let Some(_gw) = &self.env.gw {
            // placeholder for any future gateway validation
        }
        if let Some(eco) = &self.economics {
            // Validate that agreement_hash is a legal ActionHash
            let _ = ActionHash::try_from(&eco.agreement_hash)
                .context("economics.agreementHash must be a valid ActionHash")?;
            // Validate that payor is a legal AgentPubKey
            let _ = AgentPubKey::try_from(&eco.payor_unyt_agent_pub_key)
                .context("economics.payorUnytAgentPubKey must be a valid AgentPubKey")?;
        }
        if let Some(calls) = &self.app.init_zome_calls {
            for call in calls {
                if call.fn_name.trim().is_empty() {
                    bail!("app.init_zome_calls[].fn_name must be non-empty");
                }
                // payload is any valid JSON, including null – already enforced by type
                let _ = &call.payload;
            }
        }

        // economics requester pub key, price sheet: allow empty or non-empty strings
        Ok(())
    }
}

#[derive(Debug, Parser)]
#[command(
    name = "happ_config_file",
    version,
    about = "Create and validate JSON config files"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Create a template configuration file
    Create {
        /// Optional name; output file will be <name>_config.json
        #[arg(long)]
        name: Option<String>,
        /// Include gateway section in the created file
        #[arg(long)]
        gateway: bool,
        /// Include economics section in the created file
        #[arg(long)]
        economics: bool,
        /// Include an example init_zome_calls block in the created file
        #[arg(long = "init-zome-calls")]
        init_zome_calls: bool,
    },
    /// Validate a configuration file
    Validate {
        /// Path to the JSON file to validate
        #[arg(short, long)]
        input: PathBuf,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Create {
            name,
            gateway,
            economics,
            init_zome_calls,
        } => do_create(name, gateway, economics, init_zome_calls)?,
        Commands::Validate { input } => do_validate(input)?,
    }
    Ok(())
}

fn do_create(
    name: Option<String>,
    include_gateway: bool,
    include_economics: bool,
    include_init_calls: bool,
) -> Result<()> {
    // Determine output file name and app.name based on optional name
    let (output, app_name): (PathBuf, String) = if let Some(provided_name) = name {
        let name_re = Regex::new(r"^[a-z0-9_]+$").unwrap();
        if provided_name.is_empty() || !name_re.is_match(&provided_name) {
            bail!("name must be lowercase alphanumeric with underscores");
        }
        (
            PathBuf::from(format!("{}_config.json", provided_name)),
            provided_name,
        )
    } else {
        (
            PathBuf::from("example_happ_config.json"),
            "example_happ".to_string(),
        )
    };

    let template = ConfigFile {
        app: App {
            name: app_name,
            version: "0.1.0".to_string(),
            happ_url: "https://github.com/example/v0.1.0/example_happ.happ".to_string(),
            modifiers: Modifiers {
                network_seed: "0000-0000-0000-0000-0000".to_string(),
                properties: "".to_string(),
            },
            init_zome_calls: if include_init_calls {
                Some(vec![InitZomeCall {
                    fn_name: "some_zome_fn".to_string(),
                    payload: JsonValue::Null,
                }])
            } else {
                None
            },
        },
        env: Env {
            holochain: Holochain {
                version: "".to_string(),
                flags: vec!["".to_string()],
                bootstrap_url: "".to_string(),
                signal_server_url: "".to_string(),
                stun_server_urls: vec!["".to_string()],
            },
            gw: if include_gateway {
                Some(Gateway {
                    enable: true,
                    allowed_fns: vec!["".to_string()],
                    dns_props: vec!["".to_string()],
                })
            } else {
                None
            },
        },
        economics: if include_economics {
            let agent_hash: AgentPubKeyB64 =
                AgentPubKey::try_from("uhCAkJCuynkgVdMn_bzZ2ZYaVfygkn0WCuzfFspczxFnZM1QAyXoo")
                    .unwrap()
                    .into();
            let agreement_hash: ActionHashB64 =
                ActionHash::try_from("uhCkkWCsAgoKkkfwyJAglj30xX_GLLV-3BXuFy436a2SqpcEwyBzm")
                    .unwrap()
                    .into();
            Some(Economics {
                payor_unyt_agent_pub_key: agent_hash.to_string(),
                agreement_hash: agreement_hash.to_string(),
                price_sheet: "".to_string(),
            })
        } else {
            None
        },
    };

    let json = serde_json::to_string_pretty(&template)?;
    fs::write(&output, json).with_context(|| format!("writing to {}", output.display()))?;
    println!("Wrote template to {}", output.display());
    Ok(())
}

fn do_validate(input: PathBuf) -> Result<()> {
    let content =
        fs::read_to_string(&input).with_context(|| format!("reading {}", input.display()))?;
    let cfg: ConfigFile = serde_json::from_str(&content).context("invalid JSON structure")?;
    cfg.validate()?;
    println!("{} is valid", input.display());
    Ok(())
}
