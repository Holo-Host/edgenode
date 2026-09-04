# Log-Harvester Quickstart (Unyt Integration)

Connect an Edge Node to the Unyt billing pipeline using the harvester container variant. The harvester reads from a `log-collector` service, aggregates usage data, and parks invoices on Unyt Agreements via an embedded Holochain conductor.

See [Docker README.md](./README.md) for general Edge Node setup. The harvester image is built from [Dockerfile.harvester](./Dockerfile.harvester).

For upstream docs, see [unytco/log-harvester](https://github.com/unytco/log-harvester).

## How it works

```
log-collector (Cloudflare Worker)
  → edgenode-harvester (this container)
      ├── Holochain conductor (admin: 4444, app: 4445)
      ├── unyt.happ (installed at first startup)
      └── log-harvester (Node.js, runs on a daily loop)
            → Unyt Agreements (parked spend invoices)
```

On first startup the container:
1. Starts the Holochain conductor
2. Installs and enables `unyt.happ`
3. Attaches an app websocket on port 4445
4. Initializes the harvester config (generates credentials, registers with log-collector)
5. Runs the harvester loop

On subsequent restarts, credentials are automatically refreshed and `lastInvoice` is preserved so no billing data is lost.

## Prerequisites

- Docker installed
- A running `log-collector` instance and its admin secret
- Network access from the container to `COLLECTOR_URL`

## Step-by-step

### 1. Pull the image

```bash
docker login ghcr.io
docker pull ghcr.io/holo-host/edgenode-harvester
```

Images are available from [GitHub Packages](https://github.com/Holo-Host/edgenode/pkgs/container/edgenode-harvester).

The image pins [unytco/unyt-sandbox](https://github.com/unytco/unyt-sandbox)'s `unyt.happ` to v0.104.0 via the `UNYT_HAPP_VERSION` build arg; unyt releases from v0.101.0 on are Holochain 0.7 builds. To pin a different version, build locally:

```bash
# Clone log-harvester source first (required for the COPY step)
git clone --depth 1 --branch feat/adapt-to-holo-hosting-agreement https://github.com/unytco/log-harvester.git docker/log-harvester-src

docker buildx build docker/ --file docker/Dockerfile.harvester \
  --build-arg UNYT_HAPP_VERSION=v0.104.0 \
  --tag my-edgenode-harvester \
  --load
```

### 2. Start the container

```bash
docker run --name harvester -dit \
  -v $(pwd)/holo-data:/data \
  -p 4444:4444 \
  -p 4445:4445 \
  -e COLLECTOR_URL=https://your-log-collector.unyt.dev \
  -e ADMIN_SECRET=your-admin-secret \
  -e LAIR_PASSWORD=your-lair-password \
  -e LANE_DEFINITION_IDS=uhCkk... \
  ghcr.io/holo-host/edgenode-harvester
```

### 3. Watch startup

First startup takes longer — the conductor needs to initialize its keystore and install the hApp:

```bash
docker logs -f harvester
# Watch startup.log for progress
docker exec -it harvester tail -f /data/logs/startup.log
```

Look for `Starting log-harvester service...` to confirm the harvester is running.

### 4. Verify

Check the conductor is running:

```bash
docker exec -it harvester pgrep holochain
```

Check the unyt hApp is installed:

```bash
docker exec -it harvester hc client call -p 4444 list-apps
```

Check the harvester config was initialized:

```bash
docker exec -it harvester cat /data/log-harvester/config.json
```

Check the harvester is running and reporting:

```bash
docker exec -it harvester tail -f /data/logs/log-harvester.log
```

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `COLLECTOR_URL` | Log-collector endpoint URL | (required) |
| `ADMIN_SECRET` | Log-collector admin secret | (required) |
| `LAIR_PASSWORD` | Lair keystore password | (required) |
| `HC_APP_ID` | Installed Unyt hApp ID | `unyt` |
| `HC_NETWORK_SEED` | Network seed for hApp installation | `network-seed` |
| `HC_ADMIN_PORT` | Holochain admin websocket port | `4444` |
| `HC_APP_PORT` | Holochain app websocket port | `4445` |
| `LOG_FOR_TODAY` | Query today's UTC range instead of yesterday's (useful when testing same-day submissions) | `false` |
| `RUST_LOG` | Holochain log level | `info` |
| `LANE_DEFINITION_IDS` | Lane definition hash(es) the agreement pins parks/executions to, comma separated | (required) |
| `UNIT_INDEX_STORAGE` | Service-unit index the agreement meters storage on | `3` |
| `UNIT_INDEX_GOSSIP` | Service-unit index the agreement meters gossip/bandwidth on | `2` |
| `INVOICE_PERIOD_MS` | Invoicing period in ms (window and minimum gap) | `86400000` |

## Persistent data

All state is stored under the `/data` volume:

| Path | Contents |
|------|----------|
| `/data/holochain/` | Conductor state, DHT, keystore |
| `/data/log-harvester/` | Harvester config (`config.json`) |
| `/data/logs/holochain.log` | Conductor logs |
| `/data/logs/log-harvester.log` | Harvester output |
| `/data/logs/startup.log` | Startup sequence log |

Map `/data` to a named volume or host path to persist across container restarts:

```bash
-v $(pwd)/holo-data:/data
```

## Port reference

| Port | Purpose |
|------|---------|
| `4444` | Holochain admin websocket |
| `4445` | Holochain app websocket (used by log-harvester) |

## Running the test suite

```bash
./run_harvester_tests.sh
```

Builds the image, starts all required services, and runs startup, process, connectivity, and end-to-end pipeline tests. See [TESTING.md](./TESTING.md) for details.

## Troubleshooting

**Harvester fails to initialize config**
- Check `COLLECTOR_URL` is reachable from the container
- Verify `ADMIN_SECRET` is correct
- Check `/data/logs/startup.log` for the specific error

**`unyt.happ` install fails**
- Check `/data/logs/startup.log` for hApp installation errors
- The conductor must be fully started before the hApp is installed; the run script waits automatically but a slow keystore initialization can cause a timeout

**Credentials stale after restart**
- Normal behavior — credentials are automatically refreshed on every restart
- The `lastInvoice` timestamp is preserved so no billing period is skipped
