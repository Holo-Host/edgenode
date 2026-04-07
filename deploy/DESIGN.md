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
| `edgenode` | `ghcr.io/holo-host/edgenode` | 1+ | conductor, h2hc-linker, caddy, log-sender |
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
| h2hc-linker | `ENABLE_LINKER` | `H2HC_LINKER_ADMIN_SECRET` is set |
| Caddy (reverse proxy + TLS) | `ENABLE_CADDY` | `CADDY_DOMAIN` is set |
| log-sender | `ENABLE_LOG_SENDER` | `LOG_SENDER_ENDPOINT` is set |
| wdocker | `ENABLE_WDOCKER` | explicit |

The **harvester variant** (`Dockerfile.harvester`) does not include h2hc-linker or Caddy. It runs a Holochain conductor (Unyt hApp) and the Node.js log-harvester.

### h2hc-linker Packaging

h2hc-linker is a separate Rust binary from a separate repo. It is included in the standard edgenode image at build time, pinned via a build argument:

```dockerfile
ARG LINKER_VERSION=0.1.0
RUN wget https://github.com/holo-host/h2hc-linker/releases/download/v${LINKER_VERSION}/h2hc-linker-x86_64-unknown-linux-gnu \
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
  -e ENABLE_CADDY=1 \
  -e ENABLE_LINKER=1 \
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
  Makefile                     # make staging / make production / make destroy

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
make staging-init    # tofu init
make staging-apply   # tofu apply -var-file=staging.tfvars
```

`tofu apply` provisions VMs with cloud-init `user_data` that mounts the persistent volume, pulls the container image, and starts the container. The joining service Worker is deployed via `wrangler deploy` as part of the same step.

### Subsequent Deploys

- **Cloud/config changes**: `make staging-apply`
- **Container image update**: replace the VM — `tofu apply -replace=hcloud_server.edgenode[0] -var-file=staging.tfvars`. The persistent volume is reattached; Holochain data is preserved.

### Staging → Production Promotion

```bash
source deploy/.env.production
make production-init
make production-apply
```

---

## Open Questions

1. **Number of edgenode VMs**: The design supports N edgenode VMs. For staging, 2 is the minimum for meaningful DHT arc coverage. Production may warrant more. Each VM gets its own `linker.<n>.<domain>` DNS record and is registered separately in Cloudflare KV.

2. **log-collector deployment**: ✓ Resolved — see [Appendix A](#appendix-a-cloudflare-worker-deployment-spike). The log-collector deploys cleanly via OpenTofu. The joining service Worker must continue to use `wrangler deploy` until `@holo-host/lair`'s libsodium WASM dependency is resolved.

3. **OpenTofu state backend**: For a single operator, local state is acceptable. For team use, Hetzner Object Storage is the preferred remote state backend — it is S3-compatible, so the standard OpenTofu S3 backend works with an endpoint override (`https://fsn1.your-objectstorage.com`), and it keeps all infrastructure costs on Hetzner.

4. **Harvester VM sizing**: ✓ Resolved — `cx22` (2 vCPU, 4 GB RAM), same as the edgenode. The harvester runs a full Holochain conductor (Unyt hApp) plus Node.js log-harvester; 2 GB is insufficient.

6. **Ansible**: Deferred. Cloud-init covers the current scope. Ansible should be reconsidered if operational needs grow (rolling updates across many nodes, configuration drift correction, complex post-boot sequencing).

5. **Harvester bootstrap**: The harvester's Unyt conductor must be whitelisted in the joining service before it can install the Unyt hApp. The process (based on `unytco/automation/scripts/deploy.sh`) is:
   - Generate an agent key via the conductor admin API
   - Add it to the joining service's `allowed_agents` list and enable the `agent_allow_list` auth method
   - Redeploy the joining service (via `wrangler deploy`)
   - Install the Unyt hApp via the admin API, signing zome calls through lair

   Open sub-questions:
   - Does this bootstrap step run as part of the Ansible `harvester` role (fully automated), or is it a separate one-time operator step?
   - How is the lair passphrase managed for the harvester conductor — same `LAIR_PASSWORD` env var as the edgenode, or a separate secret?
   - Is the agent key stable across conductor resets, or does the joining service whitelist need to be updated on each reset?

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
