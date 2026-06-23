# edgenode-flower

A Docker image variant that bundles a Holochain conductor with a Flower SuperNode (and SuperLink capability for Mode C), connected by a Python conductor API bridge (`fl-bridge`).

Each container is a **single participating machine** in a federated learning federation. A hospital with ten imaging machines runs ten `edgenode-flower` containers — one per machine, each with its own Holochain agent identity and local training data.

The Holochain layer ([pollen hApp](https://github.com/Holo-Host/pollen)) provides audit trail, governance, and round coordination. The Flower layer performs the actual model training. The bridge connects the two.

---

## Deployment modes

| Mode | `FLOWER_DEPLOYMENT_MODE` | SuperLink | Description |
|---|---|---|---|
| **Overlay** | `overlay` | External, pre-existing | Flower connects to an existing SuperLink. Bridge records a tamper-evident audit trail per machine. No changes to existing infrastructure. |
| **Augmented** | `augmented` | External, pre-existing | As overlay, but strategy changes require on-chain governance ratification before the SuperLink may apply them. |
| **Decentralized** | `decentralized` | None (rotates per round) | No permanent SuperLink. The pollen `round_coordination` zome elects a designated aggregator per round; that machine's bridge activates a temporary SuperLink. |

Start with **overlay** — it requires no changes to an existing Flower deployment and delivers audit trail immediately.

---

## Quick start

### Overlay mode (existing SuperLink)

```sh
docker pull ghcr.io/holo-host/edgenode-flower

docker run --name edgenode-flower -dit \
  -v $(pwd)/holo-data:/data \
  -p 4444:4444 \
  -p 4445:4445 \
  -p 9091:9091 \
  -e SUPERLINK_URL=grpcs://your-superlink:9093 \
  -e FLOWER_INSECURE=true \
  -e FL_MACHINE_NAME=mri-scanner-ward-3 \
  -e FL_ORG_NAME=northside-hospital \
  -e FL_JURISDICTION=EU \
  -e FL_CLIENT_APP_MODULE=myapp:FlowerClient \
  -e FL_CLIENT_APP_URL=https://example.com/packages/myapp-1.0.tar.gz \
  -e FL_HAPP_URL=https://github.com/Holo-Host/pollen/releases/latest/download/pollen.happ \
  ghcr.io/holo-host/edgenode-flower
```

### Check status

```sh
# Verify all four s6 services are running
docker exec edgenode-flower s6-rc -a list

# Tail the bridge log
docker exec edgenode-flower tail -f /data/logs/fl-bridge.log

# Tail the Flower SuperNode log
docker exec edgenode-flower tail -f /data/logs/flower-supernode.log

# View contribution audit records for this machine
docker exec edgenode-flower cat /data/flower/contributions.jsonl

# View machine and org identity
docker exec edgenode-flower cat /data/flower/identity.json
```

### Install or manage hApps

```sh
# List installed hApps
docker exec edgenode-flower list_happs

# Manually install the pollen hApp from a local file
docker exec edgenode-flower install_happ /path/to/pollen.happ
```

---

## Environment variables

### Required for overlay / augmented mode

| Variable | Description |
|---|---|
| `SUPERLINK_URL` | Address of the Flower SuperLink, e.g. `grpcs://host:9093` |

### Machine identity (required for meaningful audit records)

| Variable | Description | Example |
|---|---|---|
| `FL_MACHINE_NAME` | Human-readable name for this machine | `mri-scanner-ward-3` |
| `FL_ORG_NAME` | Organisation this machine belongs to | `northside-hospital` |
| `FL_JURISDICTION` | Regulatory jurisdiction | `EU` |

One edgenode per machine. Each machine gets a unique `FL_MACHINE_NAME`; machines belonging to the same organisation share `FL_ORG_NAME`. Governance votes in the pollen hApp are cast at org level (one vote per org regardless of machine count).

### ClientApp — training code

| Variable | Description |
|---|---|
| `FL_CLIENT_APP_MODULE` | Python module path passed as `--clientapp` to the SuperNode, e.g. `myapp:FlowerClient` |
| `FL_CLIENT_APP_URL` | pip-installable URL or package name; installed at startup before the SuperNode launches |

If neither is set the SuperNode starts but has no training code to run. The ClientApp is user-provided and not bundled in the image.

Alternatively, volume-mount your training code and set `FL_CLIENT_APP_MODULE` to reference it:

```sh
-v $(pwd)/my_training_code:/app/clientapp \
-e FL_CLIENT_APP_MODULE=clientapp.trainer:FlowerClient \
```

### pollen hApp

| Variable | Description |
|---|---|
| `FL_HAPP_URL` | URL to download the pollen `.happ` file at startup |
| `FL_HAPP_PATH` | Path to a baked-in `.happ` file (alternative to URL) |
| `FL_APP_ID` | App ID to register in the conductor (default: `fl-happ`) |
| `HC_NETWORK_SEED` | Holochain network seed — must match across all machines in the federation (default: `fl-network`) |

If neither `FL_HAPP_URL` nor `FL_HAPP_PATH` is set, the bridge starts without the pollen hApp. Audit records are written to the local JSONL log only.

### TLS

| Variable | Description |
|---|---|
| `FLOWER_INSECURE` | Set to `true` to disable TLS (development only) |
| `FLOWER_ROOT_CERT` | Path to the root CA certificate for verifying the SuperLink |

### Deployment mode

| Variable | Default | Description |
|---|---|---|
| `FLOWER_DEPLOYMENT_MODE` | `overlay` | `overlay`, `augmented`, or `decentralized` |
| `FLOWER_SUPERLINK_PORT` | `9093` | Port the temporary SuperLink binds on (Mode C aggregator role only) |

### Holochain conductor

| Variable | Default | Description |
|---|---|---|
| `HC_ADMIN_PORT` | `4444` | Conductor admin WebSocket port |
| `HC_APP_PORT` | `4445` | Conductor app WebSocket port |
| `CONDUCTOR_MODE` | _(unset)_ | Set to `false` to skip starting the conductor (testing only) |

---

## Ports

| Port | Protocol | Description |
|---|---|---|
| `4444` | WebSocket | Holochain conductor admin API |
| `4445` | WebSocket | Holochain conductor app API |
| `9091` | gRPC | Flower SuperNode — connects outbound to SuperLink |
| `9093` | gRPC | Flower SuperLink — binds when this machine is elected aggregator (Mode C only) |

Port `9091` is an outbound connection from the SuperNode to the SuperLink. You only need to publish `9091` if the SuperLink needs to reach back in (uncommon). Port `9093` only needs to be published for machines that may be elected aggregator in Mode C.

---

## Data volume

All persistent state is stored under `/data`. Mount a volume here to survive container restarts.

```
/data/
  holochain/
    etc/              ← conductor config (symlinked from /etc/holochain)
    var/              ← conductor state, keystore (symlinked from /var/local/lib/holochain)
  flower/
    identity.json     ← machine and org identity record
    contributions.jsonl  ← per-round ContributionRecords (local audit log)
  logs/
    holochain.log
    fl-bridge.log
    flower-supernode.log
    flower-superlink.log  ← written when acting as aggregator (Mode C)
```

The keystore at `/data/holochain/var/ks` contains the machine agent's private key. **Back this up.** Loss of the keystore means loss of the machine's Holochain identity and its source chain.

---

## Building locally

```sh
cd docker/

# Standard build
docker build -f Dockerfile.flower -t edgenode-flower .

# Multi-arch
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.flower \
  -t edgenode-flower \
  .
```

---

## Multi-machine federation example

A hospital running three machines in the same federation:

```sh
# Machine 1 — MRI scanner
docker run -d --name edgenode-mri \
  -v $(pwd)/data-mri:/data \
  -e FL_MACHINE_NAME=mri-scanner-ward-3 \
  -e FL_ORG_NAME=northside-hospital \
  -e FL_JURISDICTION=EU \
  -e SUPERLINK_URL=grpcs://coordinator:9093 \
  -e FLOWER_INSECURE=true \
  -e FL_CLIENT_APP_MODULE=radiology:DicomClient \
  -e HC_NETWORK_SEED=radiology-federation-v1 \
  ghcr.io/holo-host/edgenode-flower

# Machine 2 — CT scanner
docker run -d --name edgenode-ct \
  -v $(pwd)/data-ct:/data \
  -e FL_MACHINE_NAME=ct-scanner-radiology \
  -e FL_ORG_NAME=northside-hospital \
  -e FL_JURISDICTION=EU \
  -e SUPERLINK_URL=grpcs://coordinator:9093 \
  -e FLOWER_INSECURE=true \
  -e FL_CLIENT_APP_MODULE=radiology:DicomClient \
  -e HC_NETWORK_SEED=radiology-federation-v1 \
  ghcr.io/holo-host/edgenode-flower

# Machine 3 — pathology workstation
docker run -d --name edgenode-path \
  -v $(pwd)/data-path:/data \
  -e FL_MACHINE_NAME=pathology-workstation-1 \
  -e FL_ORG_NAME=northside-hospital \
  -e FL_JURISDICTION=EU \
  -e SUPERLINK_URL=grpcs://coordinator:9093 \
  -e FLOWER_INSECURE=true \
  -e FL_CLIENT_APP_MODULE=radiology:PathologyClient \
  -e HC_NETWORK_SEED=radiology-federation-v1 \
  ghcr.io/holo-host/edgenode-flower
```

All three machines share `FL_ORG_NAME` and `HC_NETWORK_SEED`, so their pollen agents are in the same DHT neighbourhood and the hospital casts a single governance vote.

---

## Process supervision

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay) as PID 1. Four services run inside:

| Service | Type | Description |
|---|---|---|
| `setup` | oneshot | Initialises `/data` directory layout and validates conductor config |
| `conductor` | longrun | Holochain conductor (admin WebSocket on 4444) |
| `fl-bridge` | longrun | Conductor API bridge: installs pollen hApp, manages Flower process, records contributions |
| `logrotate-cron` | longrun | Daily log rotation, 7-day retention |

All services depend on `setup`. `fl-bridge` waits internally for the conductor to be ready before proceeding.

---

## Relationship to pollen

The pollen hApp provides the Holochain coordination layer:

- `participant_registry` — org and machine agent identity
- `round_coordination` — FL round lifecycle, designated aggregator election (Mode C)
- `contribution_audit` — per-machine source chain records
- `governance` — org-level voting on protocol changes
- `reputation` — per-machine reliability scores

See the [pollen repository](https://github.com/Holo-Host/pollen) and [pollen PRD](https://github.com/Holo-Host/pollen/blob/main/pollen-prd.md) for full documentation.

The bridge writes contribution records to the local JSONL log in all configurations. On-chain commitment to the pollen source chain is activated automatically once `FL_HAPP_URL` or `FL_HAPP_PATH` is configured and the pollen hApp is available.

---

## See also

- [`Dockerfile.flower`](Dockerfile.flower) — image definition
- [`fl-bridge/bridge.py`](fl-bridge/bridge.py) — conductor API bridge source
- [`docker-compose.yml`](docker-compose.yml) — multi-container test environment
- [edgenode README](README.md) — base edgenode documentation
- [Harvester quickstart](LOG_HARVESTER_QUICKSTART.md) — reference for the harvester variant
