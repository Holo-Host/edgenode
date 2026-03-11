# Log-Sender Quickstart (Unyt Integration)

Connect an Edge Node to a Unyt log-collector for resource accounting.

See the [Docker README.md](./README.md) for basic Edge Node setup. The unyt image is built from [Dockerfile.unyt](./Dockerfile.unyt).

For the upstream log-sender docs, see the [Log-Sender User Guide](https://github.com/unytco/log-sender/blob/main/LOG_SENDER_USER_GUIDE.md).

## Prerequisites

- Docker installed
- Your Unyt agent public key (`uhCAk...`)
- A log-collector service endpoint URL
- A hApp with an agreement set up in Unyt

## Step-by-step

### 1. Start the unyt container

Pass the log-sender connection details as environment variables. When `install_happ` sees a config with an `economics` section, it uses these to automatically initialize log-sender, register the DNA, and start the service.

```bash
docker run --name unytnode -dit \
  -v $(pwd)/holo-data:/data \
  -p 4444:4444 \
  -e LOG_SENDER_ENDPOINT=http://your-log-collector:8787 \
  -e LOG_SENDER_UNYT_PUB_KEY=uhCAk... \
  ghcr.io/holo-host/edgenode:latest-unyt
```

Wait for the conductor to start:

```bash
docker logs -f unytnode
# Look for "Conductor ready" or similar, then Ctrl-C
```

### 2. Create a hApp config file with economics

Shell into the container:

```bash
docker exec -it unytnode su - nonroot
```

Generate a config template with the economics section:

```bash
happ_config_file create --name my_app --economics
```

This creates `my_app_config.json`. Edit it to fill in your values:

```json
{
  "app": {
    "name": "my_app",
    "version": "0.1.0",
    "happUrl": "https://github.com/your-org/your-app/releases/download/v0.1.0/your_app.happ",
    "modifiers": {
      "networkSeed": "your-network-seed",
      "properties": ""
    }
  },
  "env": {
    "holochain": {
      "version": "",
      "flags": [""],
      "bootstrapUrl": "",
      "relayUrl": ""
    }
  },
  "economics": {
    "payorUnytAgentPubKey": "",
    "agreementHash": "uhCkk...",
    "priceSheetHash": ""
  }
}
```

Key fields:
- `happUrl`: URL to your `.happ` or `.webhapp` file
- `networkSeed`: Must match other participants in the network
- `economics.agreementHash`: The Unyt agreement action hash (triggers log-sender setup)

### 3. Install the hApp

```bash
install_happ my_app_config.json
```

Because the config has an `economics.agreementHash` and the `LOG_SENDER_*` env vars are set, `install_happ` automatically:
1. Downloads and installs the hApp
2. Initializes log-sender (generates drone keypair, registers with log-collector)
3. Registers the DNA hash with the agreement (`log-sender register-dna`)
4. Starts the log-sender service

If log-sender was already initialized (config file exists at `/etc/log-sender/config.json`), it skips step 2 and only registers the new DNA.

### 4. Verify

Check the hApp is installed:

```bash
list_happs
```

Check log-sender is running:

```bash
pgrep -f "log-sender service"
```

Check log-sender output:

```bash
tail -f /data/logs/log-sender.log
```

Verify the log-sender config has a droneId (confirms registration succeeded):

```bash
jq '.droneId' /etc/log-sender/config.json
```

## Environment variables

These are used by `install_happ` to auto-initialize log-sender when a hApp config has an `economics` section. Set them via `-e` flags on `docker run`.

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_SENDER_ENDPOINT` | Log-collector URL | (required) |
| `LOG_SENDER_UNYT_PUB_KEY` | Unyt public key | (required) |
| `LOG_SENDER_REPORT_INTERVAL_SECONDS` | Reporting frequency | `60` |
| `LOG_SENDER_LOG_PATH` | Report file directory | `/var/local/lib/holochain/reports/` |

## Manual log-sender operations

If you prefer to initialize log-sender yourself instead of using environment variables:

```bash
log-sender init \
  --config-file /etc/log-sender/config.json \
  --endpoint http://your-log-collector:8787 \
  --unyt-pub-key uhCAk... \
  --report-interval-seconds 60 \
  --report-path /var/local/lib/holochain/reports/ \
  --conductor-config-path /etc/holochain/conductor-config.yaml
```

Once the config file exists, `install_happ` will skip initialization but still register the DNA and start the service.

To register a DNA separately (e.g., adding a second hApp):

```bash
log-sender register-dna \
  --config-file /etc/log-sender/config.json \
  --dna-hash "uhC0k..." \
  --agreement-id "uhCkk..."
```

To manually start the service:

```bash
log-sender service --config-file /etc/log-sender/config.json
```

## log-sender CLI Reference

### `log-sender init`

Generates a drone keypair, registers with the log-collector, and writes a config file.

| Flag | Env var | Description |
|------|---------|-------------|
| `--config-file` | `LOG_SENDER_CONFIG_FILE` | Path to write config (e.g. `/etc/log-sender/config.json`) |
| `--endpoint` | `LOG_SENDER_ENDPOINT` | Log-collector URL |
| `--unyt-pub-key` | `LOG_SENDER_UNYT_PUB_KEY` | Base64 Unyt public key |
| `--report-interval-seconds` | `LOG_SENDER_REPORT_INTERVAL_SECONDS` | Reporting frequency |
| `--report-path` | `LOG_SENDER_REPORT_PATHS` | Directory with `.jsonl` report files (repeatable, comma-separated in env) |
| `--conductor-config-path` | `LOG_SENDER_CONDUCTOR_CONFIG_PATHS` | Conductor config for DB size reporting (repeatable) |

### `log-sender register-dna`

Registers a DNA hash with an agreement for accounting.

| Flag | Env var | Description |
|------|---------|-------------|
| `--config-file` | `LOG_SENDER_CONFIG_FILE` | Path to config file |
| `--dna-hash` | | DNA hash to register |
| `--agreement-id` | | Unyt agreement action hash |
| `--price-sheet-hash` | | Optional price sheet hash |

### `log-sender service`

Runs the reporting loop.

| Flag | Env var | Description |
|------|---------|-------------|
| `--config-file` | `LOG_SENDER_CONFIG_FILE` | Path to config file |
