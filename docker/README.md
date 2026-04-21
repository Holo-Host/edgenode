# Edge Node Container

Docker containers for running Holochain and installing hApps as always-on nodes.

Two variants are available:

| Image | Description |
|-------|-------------|
| `ghcr.io/holo-host/edgenode` | Standard edge node with `log-sender` for Unyt resource accounting. See [LOG_SENDER_QUICKSTART.md](./LOG_SENDER_QUICKSTART.md). |
| `ghcr.io/holo-host/edgenode-harvester` | Harvester variant with `log-harvester` for Unyt invoice aggregation. See [LOG_HARVESTER_QUICKSTART.md](./LOG_HARVESTER_QUICKSTART.md). |

## Container Commands

These commands are available inside both container variants:

- `install_happ [-p <port>] <config.json> [node_name]` -- Install a hApp from a config file
- `uninstall_happ [-p <port>] <app_id>` -- Uninstall a hApp
- `enable_happ [-p <port>] <app_id>` -- Enable an installed hApp
- `disable_happ [-p <port>] <app_id>` -- Disable an installed hApp
- `list_happs [-p <port>]` -- List installed hApps
- `happ_config_file` -- Create/validate hApp config files (run with `--help` for usage)

Standard variant (`edgenode`) only:
- `log_tool <init|service|help>` -- Manage the Unyt log-sender service (see [LOG_SENDER_QUICKSTART.md](./LOG_SENDER_QUICKSTART.md))
- `wdocker <command>` -- Manage always-on Moss group nodes (see [EdgeNode Moss Guide](https://holo.host/files/EdgeNodeMossGuide.pdf))
- `wdaemon` -- wdocker background daemon

The default admin port is `4444`.

## Prerequisites

- Docker installed and running.

## Getting Started

### Pull the image

```sh
docker login ghcr.io
docker pull ghcr.io/holo-host/edgenode
```

Images are available from [GitHub Packages](https://github.com/Holo-Host/edgenode/pkgs/container/edgenode).

### Run the container

```sh
docker run --name edgenode -dit \
  -v $(pwd)/holo-data:/data \
  -p 4444:4444 \
  ghcr.io/holo-host/edgenode
```

The Holochain conductor starts automatically. Data persists in `./holo-data/`.

### Shell access

```sh
docker exec -it edgenode su - nonroot
```

### Install a hApp

```sh
install_happ <config.json>
```

Both `.happ` and `.webhapp` URLs are supported in the config file. The app is automatically enabled after install.

To use a non-default admin port:

```sh
install_happ -p 5555 <config.json>
```

### List / manage hApps

```sh
list_happs
enable_happ <APP_ID>
disable_happ <APP_ID>
uninstall_happ <APP_ID>
```

## Troubleshooting

Holochain logs are at `/data/logs/holochain.log` inside the container.

```sh
# From the host (with volume mount)
cat ./holo-data/logs/holochain.log

# Live tail
docker exec -it edgenode tail -f /data/logs/holochain.log

# Copy from container
docker cp edgenode:/data/logs/holochain.log .
```

Logs rotate daily with 7-day retention.

## Conductor Configuration

- Admin port: `4444`
- Config path: `/etc/holochain/conductor-config.yaml`
- Data path: `/var/local/lib/holochain`
- Keystore path: `/var/local/lib/holochain/ks`

Paths are symlinked into the `/data` volume for persistence:

- `/etc/holochain` -> `/data/holochain/etc`
- `/var/local/lib/holochain` -> `/data/holochain/var`

## Process Management

- **s6-overlay** runs as PID 1, supervising all services with automatic restart on crash
- All processes run as nonroot (UID 65532)
- Log rotation via logrotate (daily, 7-day retention, gzip compression)

Services by variant:

| Service | `edgenode` | `edgenode-harvester` | Auto-enabled when |
|---------|-----------|---------------------|-------------------|
| `setup` (oneshot) | ✓ | ✓ | always |
| `conductor` (longrun) | ✓ | ✓ | always |
| `logrotate-cron` (longrun) | ✓ | ✓ | always |
| `log-sender` (longrun) | ✓ | — | `LOG_SENDER_ENDPOINT` is set |
| `log-harvester` (longrun) | — | ✓ | always |
| `linker` (longrun) | ✓ | — | `H2HC_LINKER_BOOTSTRAP_URL` is set |
| `caddy` (longrun) | ✓ | — | `CADDY_DOMAIN` and `H2HC_LINKER_BOOTSTRAP_URL` are both set |

### Optional services: linker and Caddy

`linker` and `caddy` are off by default and enable themselves automatically based on environment variables. s6 keeps them in a dormant-but-supervised idle state (`tail -f /dev/null`) when disabled — no crash, no restart loop.

**h2hc-linker** — WebRTC signalling bridge between browser nodes and the conductor:

```sh
docker run --name edgenode -dit \
  -v $(pwd)/holo-data:/data \
  -p 4444:4444 -p 8080:8080 \
  -e H2HC_LINKER_BOOTSTRAP_URL=https://bootstrap.holo.host \
  ghcr.io/holo-host/edgenode
```

Optional linker variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `H2HC_LINKER_BOOTSTRAP_URL` | — | Required to enable the service |
| `H2HC_LINKER_ADDRESS` | `0.0.0.0` | Bind address (container default overrides upstream `127.0.0.1`) |
| `H2HC_LINKER_PORT` | `8080` | Listen port |
| `H2HC_LINKER_ADMIN_SECRET` | — | Enables auth layer between linker and joining service |
| `H2HC_LINKER_CONDUCTOR_URL` | — | Enables zome call proxying |

**Caddy** — TLS termination and reverse proxy in front of linker. Requires a public DNS record pointing at the host and ports 80/443 exposed:

```sh
docker run --name edgenode -dit \
  -v $(pwd)/holo-data:/data \
  -p 80:80 -p 443:443 -p 4444:4444 \
  -e H2HC_LINKER_BOOTSTRAP_URL=https://bootstrap.holo.host \
  -e CADDY_DOMAIN=linker.example.com \
  ghcr.io/holo-host/edgenode
```

Caddy will not start if `H2HC_LINKER_BOOTSTRAP_URL` is unset, since there would be nothing to proxy to.

## Development

### Sandbox mode

For development, you can create a sandbox instead of using the conductor:

```sh
docker exec -it edgenode su - nonroot

hc sandbox create --root /home/nonroot/ \
  --conductor-config /etc/holochain/conductor-config.yaml \
  --data-root-path /var/local/lib/holochain

hc sandbox run 0
```

Note the `admin_port` displayed. Use `-p <port>` with the hApp management commands.

For verbose output:

```sh
RUST_LOG=debug hc sandbox run 0
```

### Manual hApp install (Kando example)

```sh
export ADMIN_PORT=<port_from_sandbox>
export AGENT_KEY=$(hc s -f $ADMIN_PORT call new-agent | awk '{print $NF}')
export APP_ID="kando::v0.17.1::$AGENT_KEY"
wget https://github.com/holochain-apps/kando/releases/download/v0.17.1/kando.happ
hc s -f $ADMIN_PORT call install-app ./kando.happ "<network_seed>" --agent-key "$AGENT_KEY" --app-id "$APP_ID"
hc s -f $ADMIN_PORT call list-apps
```

### Verifying binaries

```sh
docker run --name edgenode -dit ghcr.io/holo-host/edgenode
docker exec -it edgenode /bin/sh
holochain --version
hc --version
```

### Persistence testing

```sh
docker/test_persistence.sh
```
