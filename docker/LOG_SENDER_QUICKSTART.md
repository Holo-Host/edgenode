# Log-Sender Quickstart (Unyt Integration)

Connect an Edge Node to a Unyt log-collector for resource accounting.

See the [Docker README.md](./README.md) for basic Edge Node setup. The unyt image is built from [Dockerfile.unyt](./Dockerfile.unyt).

For the upstream log-sender docs, see the [Log-Sender User Guide](https://github.com/unytco/log-sender/blob/main/LOG_SENDER_USER_GUIDE.md).

## Prerequisites

- Holochain 0.6.1 conductor with reporting enabled
- Your Unyt agent public key
- A log-collector service endpoint
- A hApp with an agreement set up in Unyt
- A happ config file with an `economics` section (generate with `happ_config_file create --economics`)

## 1. Run the unyt image

```bash
docker run --name unytnode -dit \
  -v $(pwd)/holo-data:/data \
  ghcr.io/holo-host/edgenode:latest-unyt
```

## 2. Initialize log-sender

```bash
docker exec -it unytnode su - nonroot

log-sender init \
  --config-file /etc/log-sender/config.json \
  --endpoint http://log-collector.example.com:8787 \
  --unyt-pub-key uhCAk... \
  --report-interval-seconds 60 \
  --report-path /var/local/lib/holochain/reports/ \
  --conductor-config-path /etc/holochain/conductor-config.yaml
```

This generates a drone keypair, registers with the log-collector, and writes the config.

## 3. Install a hApp with economics

The hApp config file needs an `economics` section. When `install_happ` detects this, it automatically initializes log-sender (if not already done) and registers the DNA.

```bash
install_happ my_app_config.json
```

To do the DNA registration manually:

```bash
log-sender register-dna \
  --config-file /etc/log-sender/config.json \
  --dna-hash "uhC0k..." \
  --agreement-id "uhCkk..."
```

## 4. Start log-sender service

The service polls for new JSONL report files and sends them to the log-collector.

```bash
log-sender service --config-file /etc/log-sender/config.json
```

In the container, the service is started automatically. Check status:

```bash
tail -f /data/logs/log-sender.log
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
