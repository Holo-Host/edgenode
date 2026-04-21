# Cloud Deployment Design: Edge Node + hApp Infrastructure

## Overview

This document proposes an Infrastructure-as-Code (IaC) approach for deploying Holochain hApps using Edge Node on Hetzner Cloud, with Cloudflare for the joining service, UI hosting, and log-collector. It targets:

- **Staging and production** deployments operated by Holo
- An **operator example** that hApp developers can adapt for their own deployments

Mewsfeed is used as the reference hApp throughout.

---

## Architecture

```
Browser (HWC extension)
  → Cloudflare Pages          (UI + .happ bundle)
  → Cloudflare Worker         (joining service, invite_code / agent_allow_list auth, KV)
  → Cloudflare DNS            (A record → edgenode VM public IP)
  → edgenode container        (Caddy TLS + h2hc-linker + conductor + log-sender)
       ↓ log-sender
  → Cloudflare Worker         (log-collector, KV-backed)
       ↓ polled by
  → edgenode-harvester        (conductor + Unyt hApp + log-harvester → invoices)
       ↑ joining service
  (harvester conductor whitelisted via agent_allow_list on first deploy)
```

### Hetzner VMs

| Role | Image | Count | Services enabled |
|------|-------|-------|-----------------|
| `edgenode` | `ghcr.io/holo-host/edgenode` | 2 (staging), N (production) | conductor, h2hc-linker, caddy, log-sender |
| `harvester` | `ghcr.io/holo-host/edgenode-harvester` | 1 | conductor (Unyt hApp), log-harvester |

One or more edgenode VMs can be deployed; there is one harvester per deployment. The joining service registers all edgenode linker URLs in Cloudflare KV.

### Cloudflare Resources

| Resource | Purpose |
|----------|---------|
| DNS A record | Points `linker.<domain>` at each edgenode VM's public IP |
| Pages project | Hosts the UI build and `.happ` bundle |
| Worker: joining service | Authorises HWC browser nodes (invite_code) and the harvester's Unyt conductor (agent_allow_list); shared between hApp and Unyt; stores sessions in KV |
| Worker: log-collector | Receives log-sender reports from edgenode(s), stores in KV |
| KV namespace: `SESSIONS` | Shared by joining service (sessions, linker registrations) |
| KV namespace: `LOGS` | Used by log-collector |

---

## Data Persistence

Holochain has a fully stateful architecture. Two categories of data must survive VM lifecycle events:

**Lair keystore** — contains the node's agent private keys. Loss is permanent and unrecoverable: the agent identity is gone, existing DHT relationships are orphaned, and re-bootstrapping requires a new key and re-running the joining service registration.

**Conductor databases** — source chain (the node's full authored history) and DHT shard. The source chain is unrecoverable if lost; the DHT shard can be re-synced from the network but this is slow and disruptive.

Both live under the container's `/data` directory.

### Hetzner Persistent Volumes

Each VM (edgenode and harvester) gets a dedicated Hetzner block storage volume mounted at `/data`. Volumes are managed independently of VMs in OpenTofu — a VM can be replaced (e.g. for an image update) while its volume, and all Holochain data on it, remains intact.

```
hcloud_volume.edgenode[n]  →  attached to  →  hcloud_server.edgenode[n]
hcloud_volume.harvester    →  attached to  →  hcloud_server.harvester
```

The Docker container bind-mounts the volume:

```bash
docker run -v /mnt/edgenode-data:/data ... ghcr.io/holo-host/edgenode
```

---

## Tooling

### Why OpenTofu + cloud-init

All provisioning is handled by OpenTofu:

**Cloud resource provisioning** (Cloudflare DNS/KV/Workers/Pages, Hetzner VMs, Hetzner volumes): declarative, stateful, idempotent. The Cloudflare and Hetzner Cloud providers are both mature.

**VM initialisation** is handled by cloud-init `user_data` rendered inline in the Hetzner VM resource. Cloud-init installs Docker, mounts the persistent volume, pulls the container image, and starts the container. Because Holochain data lives on the persistent volume rather than the VM disk, VMs are effectively stateless — replacement is safe.

**Why not Ansible (for now):** Ansible adds meaningful value for day-2 operations across many hosts (rolling updates, config drift correction, multi-step sequencing). For the current scope — a small number of VMs each running one container — cloud-init is sufficient and keeps the toolchain simpler. Ansible can be introduced later if operational complexity warrants it.

### Why Hetzner

- Lower cost per VM than DigitalOcean for always-on nodes that are largely idle
- EU datacenter locations suit the expected user base
- `hetznercloud/hcloud` Terraform provider is mature and well-maintained
- `cx22` (2 vCPU, 4 GB RAM) is sufficient for an edgenode or harvester running one hApp
- Persistent block storage volumes are inexpensive and S3-compatible object storage is available for OpenTofu state

---

## Edgenode Container: Service Model

The standard edgenode image is flexible — services are toggled via environment variables. s6-overlay supervises all processes; each service's `run` script exits cleanly if its toggle variable is absent, without s6 treating it as a crash.

### Services and Toggles

| Service | Toggle variable | Auto-enabled when |
|---------|----------------|-------------------|
| Holochain conductor | `CONDUCTOR_MODE` | set (existing behaviour) |
| h2hc-linker | `ENABLE_LINKER` | `H2HC_LINKER_BOOTSTRAP_URL` is set |
| Caddy (reverse proxy + TLS) | `ENABLE_CADDY` | `CADDY_DOMAIN` and `H2HC_LINKER_BOOTSTRAP_URL` are set |
| log-sender | `ENABLE_LOG_SENDER` | `LOG_SENDER_ENDPOINT` is set |
| wdocker | `ENABLE_WDOCKER` | explicit |

The **harvester variant** (`Dockerfile.harvester`) does not include h2hc-linker or Caddy. It runs a Holochain conductor (Unyt hApp) and the Node.js log-harvester.

### h2hc-linker Packaging

h2hc-linker is a separate Rust binary from a separate repo. It is included in the standard edgenode image at build time, pinned via a build argument:

```dockerfile
ARG LINKER_VERSION=0.1.1
RUN wget https://github.com/holo-host/h2hc-linker/releases/download/v${LINKER_VERSION}/h2hc-linker-linux-x86_64 \
    -O /usr/local/bin/h2hc-linker && chmod +x /usr/local/bin/h2hc-linker
```

This follows the same pattern used for Holochain binaries. `LINKER_VERSION` is updated independently of the edgenode image version.

### Caddy and Public Endpoint

Caddy replaces the need for a cloudflared tunnel. Because the edgenode runs on a Hetzner VM with a public IP, Caddy can terminate TLS directly using Let's Encrypt, given a DNS record pointing at the VM.

```
CADDY_DOMAIN=linker.example.com
```

Caddy serves the h2hc-linker on HTTPS at that domain. The container must expose ports 80 and 443:

```bash
docker run \
  -p 80:80 -p 443:443 -p 4444:4444 \
  -e CADDY_DOMAIN=linker.example.com \
  -e H2HC_LINKER_BOOTSTRAP_URL=https://bootstrap.holo.host \
  -e H2HC_LINKER_ADMIN_SECRET=... \
  ghcr.io/holo-host/edgenode
```

The linker URL is stable — it does not change across container or VM restarts — so Cloudflare KV does not need to be re-seeded after restarts.

---

## Secrets and Configuration

All secrets are passed as environment variables. This matches the pattern established in `mewsfeed/deploy/deploy.sh` and the edgenode container's own env-var-based configuration (`LOG_SENDER_ENDPOINT`, `LOG_SENDER_UNYT_PUB_KEY`, etc.).

Secrets are never committed. Operators copy `.env.example` to `.env.staging` or `.env.production`, fill in their values, and source the file before running any tooling.

```bash
cp deploy/.env.example deploy/.env.staging
$EDITOR deploy/.env.staging
source deploy/.env.staging
make staging
```

OpenTofu reads secrets via `TF_VAR_*` prefixed variables and passes them into cloud-init `user_data` templates.

### Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `HCLOUD_TOKEN` | OpenTofu | Hetzner Cloud API token |
| `CLOUDFLARE_ACCOUNT_ID` | OpenTofu | Cloudflare account ID |
| `CLOUDFLARE_API_TOKEN` | OpenTofu | Cloudflare API token (Workers, Pages, KV, DNS) |
| `CLOUDFLARE_WORKERS_SUBDOMAIN` | OpenTofu | Workers subdomain (e.g. `myaccount`) |
| `CLOUDFLARE_ZONE_ID` | OpenTofu | Zone ID for DNS A record management |
| `CADDY_DOMAIN` | edgenode | Public domain for linker HTTPS endpoint |
| `LINKER_ADMIN_SECRET` | edgenode, joining service | Shared secret between linker and joining service |
| `INVITE_CODES` | joining service | Comma-separated invite codes |
| `LOG_SENDER_ENDPOINT` | edgenode | Log-collector URL |
| `LOG_SENDER_UNYT_PUB_KEY` | edgenode | Unyt agent public key |
| `LAIR_PASSWORD` | edgenode | Lair keystore password |
| `COLLECTOR_URL` | harvester | Log-collector URL |
| `ADMIN_SECRET` | harvester | Log-collector admin secret |
| `SSH_PUBLIC_KEY` | OpenTofu | SSH public key added to VMs (for operator access and harvester bootstrap) |

---

## Directory Structure

```
deploy/
  DESIGN.md                    # This document
  .env.example                 # Template for all secrets (committed)
  scripts/
    staging-apply.sh           # tofu init + apply for staging
    production-apply.sh        # tofu init + apply for production
    bootstrap-harvester.sh     # one-time harvester bootstrap (runs bootstrap container)

  tofu/
    cloudflare.tf              # DNS, Pages, joining service Worker, log-collector Worker, KV
    hetzner.tf                 # VMs, persistent volumes, SSH key, firewall, cloud-init
    variables.tf               # All input variables with descriptions
    outputs.tf                 # VM IPs, Worker URLs, KV namespace IDs, domain names
    staging.tfvars             # Non-secret staging config (committed)
    production.tfvars          # Non-secret production config (committed)

  cloud-init/
    edgenode.yml.tpl           # Rendered by OpenTofu templatefile(): mounts volume,
                               #   pulls image, runs container, calls install_happ
    harvester.yml.tpl          # Same pattern for harvester container

  mewsfeed-config.json.example # hApp config template for operators
```

All container configuration (linker, Caddy, log-sender, etc.) is passed via environment variables rendered into the cloud-init template — no separate configuration management layer needed.

---

## Workflow

### First-time Setup

```bash
# 1. Copy and populate secrets
cp deploy/.env.example deploy/.env.staging
$EDITOR deploy/.env.staging
source deploy/.env.staging

# 2. Provision everything (VMs, volumes, Cloudflare resources)
./deploy/scripts/staging-apply.sh

# 3. Bootstrap the harvester (one-time)
./deploy/scripts/bootstrap-harvester.sh
```

`staging-apply.sh` runs `tofu init` + `tofu apply`. Cloud-init on each VM mounts the persistent volume, pulls the container image, and starts the container. The joining service Worker is deployed via `wrangler deploy` as part of the same step.

`bootstrap-harvester.sh` runs the bootstrap container, which generates the harvester's agent key, whitelists it in the joining service, and installs the Unyt hApp.

### Subsequent Deploys

- **Cloud/config changes**: `./deploy/scripts/staging-apply.sh`
- **Container image update**: replace the VM — `tofu apply -replace=hcloud_server.edgenode[0] -var-file=staging.tfvars`. The persistent volume is reattached; Holochain data is preserved.

### Staging → Production Promotion

```bash
source deploy/.env.production
./deploy/scripts/production-apply.sh
./deploy/scripts/bootstrap-harvester.sh
```

---

## Disaster Recovery

### What must be preserved

| Data | Location | Consequence of loss |
|------|----------|---------------------|
| Lair keystore | `/data/lair/` | **Permanent.** Agent identity is gone; re-bootstrapping requires a new key, joining service re-registration, and loss of all existing DHT associations. |
| Conductor source chains | `/data/holochain/` | **Permanent per author.** Each node's own authored data is unrecoverable. |
| Conductor DHT shard | `/data/holochain/` | **Recoverable.** Can be re-synced from the network, but this is slow and disrupts hosting. |
| OpenTofu state | remote backend (object storage) | **Recoverable with effort.** Existing infrastructure can be re-imported, but state loss makes `tofu apply` dangerous until state is reconstructed. |

Config and secrets are not stored on VMs — they are held by the operator and re-applied at provision time.

### Backup strategy

**Primary: Hetzner volume snapshots**

Each persistent volume is snapshotted daily via the Hetzner API. Snapshots are point-in-time copies of the block device; a new volume can be created from any snapshot and attached to a replacement VM.

```bash
# Snapshot a volume (run from operator machine or a cron on the VM host)
hcloud volume create-snapshot <volume-id> --description "edgenode-daily-$(date +%Y%m%d)"
```

Snapshots should be taken with the container stopped to ensure database consistency:

```bash
docker stop edgenode
hcloud volume create-snapshot <volume-id> --description "edgenode-$(date +%Y%m%d)"
docker start edgenode
```

Downtime per snapshot is typically under a minute.

**Retention:** keep 7 daily snapshots. Hetzner charges by snapshot size; for a 10 GB volume this is minimal.

**OpenTofu state**

The state backend (Hetzner Object Storage) must have versioning enabled on the bucket. This provides automatic state history and protects against accidental `tofu destroy` or state corruption.

```hcl
# In backend config
backend "s3" {
  ...
  # Enable versioning on the bucket in Hetzner console
}
```

### Recovery procedures

**Scenario 1: VM failure, volume intact** *(most common)*

The persistent volume survives independently of the VM. Recovery is a normal `tofu apply`:

```bash
# OpenTofu detects the VM is gone, recreates it, reattaches the existing volume
tofu apply -var-file=staging.tfvars
```

Cloud-init on the new VM mounts the volume and restarts the container. Agent identity and all data are preserved. Recovery time: ~5 minutes.

**Scenario 2: Volume lost or corrupted, snapshot available**

```bash
# 1. Create a new volume from the most recent snapshot
hcloud volume create --snapshot <snapshot-id> --name edgenode-data-restored --size 10

# 2. Update the volume resource reference in tofu state or tfvars, then apply
tofu apply -var-file=staging.tfvars
```

Data loss is bounded by the snapshot interval (at most 24 hours of source chain activity with daily snapshots).

**Scenario 3: Both volume and snapshots lost** *(catastrophic)*

Agent identity is unrecoverable. Steps:
1. Provision fresh VM and volume via `tofu apply`
2. Re-run harvester bootstrap (generate new agent key, update joining service whitelist, redeploy)
3. Reinstall hApp — existing users will need to re-join; hosted data that was solely on this node is lost

This scenario is prevented by maintaining snapshots. There is no mitigation once it occurs.

### Objectives

**RTO (Recovery Time Objective)** — how long it takes to restore service after a failure.
**RPO (Recovery Point Objective)** — how much data can be lost, measured as the maximum time gap between the last backup and the failure.

| Metric | Target |
|--------|--------|
| RTO — VM failure, volume intact | < 10 minutes |
| RTO — volume restore from snapshot | < 30 minutes |
| RPO — daily snapshots | < 24 hours |
| RPO — lair keystore | 0 — lair is only written on first init; once snapshotted it does not change |

---

## Open Questions

1. **Number of edgenode VMs**: ✓ Resolved — 2 edgenode VMs for staging, plus 1 harvester VM (3 VMs total). Two edgenodes is the minimum for meaningful DHT arc coverage and exercises multi-node code paths. Production deployments for larger communities will scale beyond this; the design supports N edgenodes. Each edgenode gets its own `linker.<n>.<domain>` DNS record and is registered separately in Cloudflare KV.

2. **log-collector deployment**: ✓ Resolved — see [Appendix A](#appendix-a-cloudflare-worker-deployment-spike). The log-collector deploys cleanly via OpenTofu. The joining service Worker must continue to use `wrangler deploy` until `@holo-host/lair`'s libsodium WASM dependency is resolved.

3. **OpenTofu state backend**: ✓ Resolved (for now) — local state for the staging PoC. For team use, Hetzner Object Storage is the preferred remote state backend — it is S3-compatible, so the standard OpenTofu S3 backend works with an endpoint override (`https://fsn1.your-objectstorage.com`), and it keeps all infrastructure costs on Hetzner. Migrate when more than one operator needs to run `tofu apply`.

4. **Harvester VM sizing**: ✓ Resolved — `cx22` (2 vCPU, 4 GB RAM), same as the edgenode. The harvester runs a full Holochain conductor (Unyt hApp) plus Node.js log-harvester; 2 GB is insufficient.

5. **Harvester bootstrap**: ✓ Resolved — the harvester's Unyt conductor must be whitelisted in the joining service before it can install the Unyt hApp. The process (based on `unytco/automation/scripts/deploy.sh`) is:
   - Generate an agent key via the conductor admin API
   - Add it to the joining service's `allowed_agents` list and enable the `agent_allow_list` auth method
   - Redeploy the joining service (via `wrangler deploy`)
   - Install the Unyt hApp via the admin API, signing zome calls through lair

   This is a one-time step per deployment (the agent key is stable for the lifetime of the persistent volume). It runs after `tofu apply` as a separate bootstrap phase via `bootstrap-harvester.sh`, which runs a Docker image (`ghcr.io/holo-host/edgenode-bootstrap`) so no local Rust/Node tooling is required. The lair passphrase for the harvester conductor is managed as a separate `HARVESTER_LAIR_PASSWORD` env var.

6. **Ansible**: Deferred. Cloud-init covers the current scope. Ansible should be reconsidered if operational needs grow (rolling updates across many nodes, configuration drift correction, complex post-boot sequencing).

7. **Platform: self-registering harvester**: The bootstrap container approach is sufficient for the staging PoC but does not scale to a multi-customer platform. See [Appendix B](#appendix-b-platform-track--self-registering-harvester) for a full design. Requires a new machine-to-machine admin API on the joining service; should be scoped as a platform-track requirement.

---

## Operator Adaptation

Operators who want to run their own edgenode deployment for a different hApp can:

1. Copy the `deploy/` directory into their project (or reference it as a submodule)
2. Replace `mewsfeed-config.json.example` with their own hApp config
3. Set their own values in `staging.tfvars` / `production.tfvars` (project name, region, VM count, domain)
4. Supply secrets via their own `.env.*` files

The cloud-init templates are hApp-agnostic — `install_happ` reads from the config file, so no template changes are needed to switch hApps.

---

## Appendix A: Cloudflare Worker Deployment Spike

**Branch:** `feat/cloud-deployment-iac`
**Spike code:** `deploy/spike/`
**Date:** 2026-04-07

### Questions

1. Can `cloudflare_worker_script` handle a TypeScript Worker that requires a wrangler/esbuild build step?
2. Can esbuild resolve the joining service's cross-directory imports (`../../../joining-service/src/...`)?
3. Do KV namespace and D1 database bindings wire up correctly via the provider?

### Setup notes

- The Cloudflare Terraform provider **v4.x does not have** `cloudflare_worker`, `cloudflare_worker_version`, or `cloudflare_workers_deployment`. These resources exist in **v5.x** (tested against v5.18.0). Use `version = "~> 5.0"` in the provider block.
- The joining service Worker requires the `nodejs_compat` compatibility flag (for `node:crypto`).
- The `cloudflare_worker` resource has `subdomain = { enabled = false }` by default. Set `enabled = true` to route `<name>.<account>.workers.dev` traffic.
- The `cloudflare_d1_database` resource in v5 requires `read_replication = { mode = "disabled" }` to be set explicitly to avoid a provider drift error on subsequent applies.
- Required API token permissions: **Workers Scripts: Edit**, **Workers KV Storage: Edit**, **D1: Edit**, **Account Settings: Read**.

### Findings

**Question 2 — Cross-directory imports: YES**

esbuild resolves the joining service's cross-directory imports at bundle time with no issues. Running esbuild from the repo root with `NODE_PATH` pointing at the joining-service `node_modules` is sufficient.

**Question 3 — KV and D1 bindings: YES**

Both binding types wire up correctly via the `bindings` array on `cloudflare_worker_version`. The log-collector Worker with its D1 binding deployed and responded to HTTP requests.

**Question 1 — esbuild bundling: PARTIAL**

The log-collector Worker (pure TypeScript, no WASM dependencies) deployed and runs correctly via OpenTofu.

The joining service Worker fails to start (Cloudflare error 1042) due to its dependency on `@holo-host/lair`, which wraps `libsodium-wrappers`. The `libsodium` package is compiled by Emscripten and loads its `.wasm` binary at module initialisation time using `new URL(...)` path resolution. This fails in the Cloudflare Workers runtime, where there is no filesystem.

This is **not a new problem with the joining service** — it has always existed. `wrangler deploy` handles it transparently: Wrangler scans for `.wasm` files during bundling, extracts them, and uploads them as named Workers module bindings, rewriting the imports accordingly. Our esbuild-only approach bypasses this step.

### Decision

| Worker | Deployment method |
|--------|------------------|
| log-collector | OpenTofu (`cloudflare_worker` + `cloudflare_worker_version` + `cloudflare_workers_deployment`) |
| joining service | `wrangler deploy` (unchanged from current practice) |

OpenTofu manages the KV namespace and D1 database as infrastructure; the joining service Worker deployment remains a `wrangler` step.

### Joining service WASM issue — options for `@holo-host/lair` developer

The joining service Worker crashes at startup whenever `@holo-host/lair` is imported, regardless of whether membrane proofs are enabled. The underlying cause is `libsodium-wrappers`' WASM loading strategy. Three options:

1. **Lazy-load `LairProofGenerator`** in `mewsfeed`'s `worker-entry.ts` — use a dynamic `import()` inside `buildProofGenerator()` so libsodium only initialises when membrane proofs are actually needed. Unblocks deployment for configs where `membrane_proof.enabled` is false; does not fix the root cause.

2. **Upload `libsodium.wasm` as a named Workers module** — Cloudflare Workers supports WASM via ES module imports (`import wasm from './sodium.wasm'`). This would require a custom Emscripten build of libsodium that accepts a pre-compiled `WebAssembly.Module` rather than fetching by path. No maintained npm package does this today.

3. **Replace libsodium with a pure-JS ed25519 library in `@holo-host/lair`** — `@noble/ed25519` or `@noble/curves` are well-audited, pure TypeScript, and bundle cleanly with esbuild. This removes the WASM dependency entirely and would make `@holo-host/lair` work in any JS environment (Workers, Deno, browsers) without bundler workarounds. This is the recommended long-term fix.

---

## Appendix B: Platform-Track — Self-Registering Harvester

### Problem

The current harvester bootstrap process (Option A) requires an operator to run `bootstrap-harvester.sh` after each new deployment. The script:

1. SSHs into the harvester VM to access the conductor admin port
2. Generates an agent key via the admin API
3. Edits the joining service config file to add the key to `allowed_agents`
4. Redeploys the joining service via `wrangler deploy`
5. Installs the Unyt hApp

This is acceptable for a single managed deployment but does not scale to a platform offering multiple customer deployments. Each new customer deployment would require an operator to run this script manually, introducing a human bottleneck and an operational risk (forgotten bootstrap, config drift).

### Proposed solution: joining service admin API

The joining service should expose a machine-to-machine admin endpoint for agent registration. On first start, the harvester conductor:

1. Generates its agent key (standard Holochain conductor behaviour)
2. Calls the joining service admin API with the key and a shared `JOINING_SERVICE_ADMIN_SECRET`
3. The joining service adds the key to its `allowed_agents` store in KV — no config file edit, no redeployment
4. The harvester conductor proceeds to install the Unyt hApp

The entire bootstrap becomes automatic with no operator involvement. New customer deployments provision and bootstrap themselves via `tofu apply` alone.

### Design sketch

**New joining service endpoint:**

```
POST /admin/agents
Authorization: Bearer <JOINING_SERVICE_ADMIN_SECRET>
Content-Type: application/json

{ "agent_key": "<base64-agent-pubkey>" }
```

The joining service stores approved agents in the `SESSIONS` KV namespace under a dedicated key prefix (e.g. `approved_agent:<key>`). The existing `agent_allow_list` auth method checks KV at request time rather than reading from static config.

**Harvester cloud-init change:**

The `harvester.yml.tpl` cloud-init template would call the admin API after the conductor is ready, replacing the separate `bootstrap-harvester.sh` step entirely:

```bash
# Wait for conductor, generate key, register with joining service
docker exec harvester register-with-joining-service \
  --joining-service-url "$JOINING_SERVICE_URL" \
  --admin-secret "$JOINING_SERVICE_ADMIN_SECRET"
```

**New secrets required:**

| Variable | Used by | Description |
|----------|---------|-------------|
| `JOINING_SERVICE_ADMIN_SECRET` | joining service, harvester | Shared secret for machine-to-machine agent registration |

### Scope

This requires changes to:

- **joining service** — new admin endpoint, KV-backed agent store, runtime `agent_allow_list` check
- **edgenode-bootstrap container** — can be retired or simplified once joining service supports this
- **cloud-init templates** — harvester template calls admin API instead of relying on separate bootstrap script
- **`deploy/scripts/bootstrap-harvester.sh`** — removed; bootstrap becomes part of `tofu apply`

### Dependencies

- Joining service admin API must be implemented first
- Can be developed independently of the staging PoC; Option A remains in place until this is ready

---

## Appendix C: Deployment Path Options

The Hetzner + Cloudflare path described in this document is one of several
viable deployment models. The edgenode container and the tooling around it are
designed to be portable — the container takes environment variables, the
persistent data lives on a mounted volume, and the bootstrap is a standalone
Docker image. Different operators have different infrastructure preferences and
cost/complexity trade-offs.

### Option A: Hetzner VMs + Cloudflare (current)

**What:** Hetzner `cx22` VMs running Docker, Cloudflare Workers for joining
service and log-collector, Cloudflare DNS.

**Tooling:** OpenTofu + cloud-init + wrangler

**Best for:** Teams operating a managed deployment for a community. Predictable
costs, EU datacenter locations, straightforward ops.

**Trade-offs:**
- Requires managing VMs and their lifecycle (image updates = VM replacement)
- Two infrastructure providers to manage (Hetzner + Cloudflare)
- Hetzner has no built-in auto-scaling

**Status:** Implemented — see `deploy/tofu/` and `deploy/scripts/`.

---

### Option B: Pure Cloudflare (Containers + Workers)

**What:** [Cloudflare Containers](https://developers.cloudflare.com/containers/)
run the edgenode and harvester images. The joining service and log-collector
remain as Workers. Everything lives in Cloudflare.

**Tooling:** OpenTofu (Cloudflare provider only) + wrangler

**Best for:** Operators who want a single-provider stack and are comfortable
with Cloudflare's pricing model. Eliminates VM management entirely.

**Key considerations:**
- Cloudflare Containers are billed per container-second, not per month — cost
  model is very different from always-on VMs; evaluate for workloads that are
  largely idle
- Persistent storage: Containers have ephemeral local storage. Holochain's
  `/data` directory would need to be backed by Cloudflare Durable Objects or
  R2 via a FUSE mount — neither is a standard pattern today. **This is the
  primary blocker for this path.**
- `lair_server_in_proc` writes to disk; the keystore must survive container
  restarts. Without durable storage, identity is lost on each restart.
- Container networking: Cloudflare Containers can communicate with Workers
  via service bindings, which simplifies the log-collector integration.
- The harvester bootstrap would need to adapt — no SSH access to containers,
  so the admin WebSocket tunnel approach requires a different mechanism
  (e.g. a Cloudflare Tunnel or the joining service platform-track API from
  Appendix B).

**Status:** Not yet implemented. Blocked on durable storage story for
Holochain's `/data`. Worth revisiting as Cloudflare's storage primitives mature.

---

### Option C: Docker Compose (self-hosters and small operators)

**What:** A `docker-compose.yml` that runs the full stack on a single machine
— edgenode container, harvester container, and a local reverse proxy. No cloud
provider accounts required beyond a domain and a public IP.

**Tooling:** `docker compose up`

**Best for:**
- Individual developers running a local or home-server deployment
- Small community operators who own hardware or a single VPS
- Local development and integration testing

**Key considerations:**
- Persistent volumes: Docker named volumes or bind mounts to a local directory;
  straightforward on a single machine
- TLS: Caddy in the edgenode container handles this automatically given a
  public domain — same as the Hetzner path
- Joining service: operators either run the joining service locally (via
  wrangler dev) or point at an existing hosted instance
- Log-collector: can run as a local Worker via `wrangler dev` or be omitted
  for development
- No OpenTofu required — `docker compose up -d` is the entire provisioning step
- Harvester bootstrap: same `ghcr.io/holo-host/edgenode-bootstrap` container
  works; the conductor admin port is accessible on `localhost` rather than via
  SSH tunnel
- **Not suitable for production community deployments** — single point of
  failure, no geographic distribution, operator must manage their own backups

**Approximate `docker-compose.yml` shape:**

```yaml
services:
  edgenode:
    image: ghcr.io/holo-host/edgenode:latest
    ports: ["80:80", "443:443", "4444:4444"]
    volumes: [edgenode-data:/data]
    environment:
      CADDY_DOMAIN: linker.example.com
      H2HC_LINKER_BOOTSTRAP_URL: ${H2HC_LINKER_BOOTSTRAP_URL}
      H2HC_LINKER_ADMIN_SECRET: ${LINKER_ADMIN_SECRET}
      LOG_SENDER_ENDPOINT: ${LOG_SENDER_ENDPOINT}
      LAIR_PASSWORD: ${LAIR_PASSWORD}
    restart: unless-stopped

  harvester:
    image: ghcr.io/holo-host/edgenode-harvester:latest
    ports: ["4444:4444"]
    volumes: [harvester-data:/data]
    environment:
      LAIR_PASSWORD: ${HARVESTER_LAIR_PASSWORD}
      COLLECTOR_URL: ${COLLECTOR_URL}
      ADMIN_SECRET: ${ADMIN_SECRET}
    restart: unless-stopped

volumes:
  edgenode-data:
  harvester-data:
```

**Status:** Not yet implemented. A well-documented Docker Compose example
would be a high-value addition for self-hosters and would also serve as the
simplest possible integration test environment for the edgenode container.

---

### Comparison

| | Hetzner + Cloudflare | Pure Cloudflare | Docker Compose |
|---|---|---|---|
| Infrastructure providers | 2 (Hetzner, Cloudflare) | 1 (Cloudflare) | 0 (self-hosted) |
| VM management | Yes | No | No |
| Persistent storage | Hetzner volumes | Blocked (see above) | Docker volumes |
| Scaling | Manual (`edgenode_count`) | Automatic (Containers) | Manual |
| Cost model | Fixed monthly (VMs) | Per-second (Containers) | Hardware / VPS cost |
| Setup complexity | Medium | Low (once available) | Low |
| Production-ready | Yes | Not yet | No |
| Status | Implemented | Future | Future |
