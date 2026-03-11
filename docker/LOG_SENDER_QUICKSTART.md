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

Pass log-sender connection details as environment variables. When `install_happ` sees a config with an `economics` section, it uses these to automatically initialize log-sender, register the DNA, and start the service.

```bash
docker run --name unytnode -dit \
  -v $(pwd)/holo-data:/data \
  -e LOG_SENDER_ENDPOINT=http://log-collector.example.com:8787 \
  -e LOG_SENDER_UNYT_PUB_KEY=uhCAk... \
  ghcr.io/holo-host/edgenode:latest-unyt
```

## 2. Install a hApp with economics

The hApp config file needs an `economics` section (generate with `happ_config_file create --economics`).

```bash
docker exec -it unytnode su - nonroot
install_happ my_app_config.json
```

`install_happ` automatically:
1. Initializes log-sender if no config exists (using the `LOG_SENDER_*` env vars)
2. Registers the DNA hash with the agreement
3. Starts the log-sender service

## 3. Verify

```bash
tail -f /data/logs/log-sender.log
```

## Manual alternative

If you prefer to initialize log-sender manually instead of using env vars:

```bash
log-sender init \
  --config-file /etc/log-sender/config.json \
  --endpoint http://log-collector.example.com:8787 \
  --unyt-pub-key uhCAk... \
  --report-interval-seconds 60 \
  --report-path /var/local/lib/holochain/reports/ \
  --conductor-config-path /etc/holochain/conductor-config.yaml
```

Once the config exists, `install_happ` will skip initialization but still register the DNA and start the service.

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
