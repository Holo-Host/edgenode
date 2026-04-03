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
  → Cloudflare Worker         (joining service, invite_code auth, KV)
  → Cloudflare DNS            (A record → edgenode VM public IP)
  → edgenode container        (Caddy TLS + h2hc-linker + conductor + log-sender)
       ↓ log-sender
  → Cloudflare Worker         (log-collector, KV-backed)
       ↓ polled by
  → edgenode-harvester        (log-harvester → Unyt invoices)
```

### Hetzner VMs

| Role | Image | Services enabled |
|------|-------|-----------------|
| `edgenode` | `ghcr.io/holo-host/edgenode` | conductor, h2hc-linker, caddy, log-sender |
| `harvester` | `ghcr.io/holo-host/edgenode-harvester` | log-harvester only |

One or more edgenode VMs can be deployed; the joining service registers all of them in Cloudflare KV.

### Cloudflare Resources

| Resource | Purpose |
|----------|---------|
| DNS A record | Points `linker.<domain>` at each edgenode VM's public IP |
| Pages project | Hosts the UI build and `.happ` bundle |
| Worker: joining service | Authorises HWC browser nodes via invite code, stores sessions in KV |
| Worker: log-collector | Receives log-sender reports from edgenode(s), stores in KV |
| KV namespace: `SESSIONS` | Shared by joining service (sessions, linker registrations) |
| KV namespace: `LOGS` | Used by log-collector |

---

## Tooling

### Why OpenTofu + Ansible

The deployment has two distinct concerns:

**Cloud resource provisioning** (Cloudflare DNS/KV/Workers/Pages, Hetzner VMs): declarative, stateful, idempotent. OpenTofu (Terraform-compatible) handles this well. The Cloudflare and Hetzner Cloud providers are both mature.

**Container and service management** (edgenode, harvester): imperative configuration of remote hosts. Ansible is agentless, idempotent, and straightforward to read for operators who are not infrastructure specialists.

Shell scripts are appropriate for local dev but are too fragile for multi-host, multi-environment deployments — no state management, no rollback, poor idempotency guarantees.

### Why Hetzner

- Lower cost per VM than DigitalOcean for always-on nodes that are largely idle
- EU datacenter locations suit the expected user base
- `hetznercloud/hcloud` Terraform provider is mature and well-maintained
- `cx22` (2 vCPU, 4 GB RAM) is sufficient for an edgenode running one hApp

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

The **harvester variant** (`Dockerfile.harvester`) does not include h2hc-linker or Caddy. It runs log-harvester only.

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

OpenTofu reads secrets via `TF_VAR_*` prefixed variables. Ansible reads them from the environment via `lookup('env', ...)`.

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
| `SSH_KEY_PATH` | Ansible | Path to SSH private key for Hetzner VMs |

---

## Directory Structure

```
deploy/
  DESIGN.md                    # This document
  .env.example                 # Template for all secrets (committed)
  Makefile                     # make staging / make production / make status / make destroy

  tofu/
    cloudflare.tf              # DNS, Pages, joining service Worker, log-collector Worker, KV
    hetzner.tf                 # Hetzner VMs (edgenode, harvester), SSH key, firewall
    variables.tf               # All input variables with descriptions
    outputs.tf                 # VM IPs, Worker URLs, KV namespace IDs, domain names
    staging.tfvars             # Non-secret staging config (committed)
    production.tfvars          # Non-secret production config (committed)

  ansible/
    inventory/
      staging.yml              # Populated from `tofu output` via Makefile
      production.yml
    roles/
      edgenode/                # docker pull, docker run with env vars, install_happ
      harvester/               # docker pull, docker run with env vars
    site.yml                   # Top-level playbook

  mewsfeed-config.json.example # hApp config template for operators
```

Note: no separate Ansible roles for linker, Caddy, or tunnel — all are managed inside the edgenode container via env vars.

---

## Workflow

### First-time Setup

```bash
# 1. Copy and populate secrets
cp deploy/.env.example deploy/.env.staging
$EDITOR deploy/.env.staging
source deploy/.env.staging

# 2. Provision cloud resources and VMs
make staging-init    # tofu init
make staging-apply   # tofu apply -var-file=staging.tfvars

# 3. Configure and start services on VMs
make staging-deploy  # ansible-playbook site.yml -i inventory/staging.yml
```

The Makefile generates `ansible/inventory/staging.yml` from `tofu output` before running Ansible, so there is no manual IP management.

### Subsequent Deploys

- **Cloud resource changes**: `make staging-apply`
- **Container/service changes**: `make staging-deploy`
- **Full redeploy**: `make staging` (runs both)

### Staging → Production Promotion

Production uses the same playbooks with different tfvars and inventory:

```bash
source deploy/.env.production
make production
```

---

## Open Questions

1. **Number of edgenode VMs**: The design supports N edgenode VMs. For staging, 2 is the minimum for meaningful DHT arc coverage. Production may warrant more. Each VM gets its own `linker.<n>.<domain>` DNS record and is registered separately in Cloudflare KV.

2. **log-collector deployment**: The log-collector is a Cloudflare Worker (see `docker/log-collector/wrangler.toml`). It can be deployed via the Cloudflare Terraform provider (`cloudflare_worker_script`) alongside the joining service Worker, or kept as a separate `wrangler deploy` step. The former is cleaner for IaC but the `cloudflare_worker_script` resource has some rough edges around bundled Workers — worth evaluating.

3. **OpenTofu state backend**: For a single operator, local state is acceptable. For team use, Hetzner Object Storage is the preferred remote state backend — it is S3-compatible, so the standard OpenTofu S3 backend works with an endpoint override (`https://fsn1.your-objectstorage.com`), and it keeps all infrastructure costs on Hetzner.

4. **Harvester VM sizing**: The harvester has lighter Holochain requirements than the standard edgenode. A `cx11` (2 vCPU, 2 GB) may be sufficient; this should be confirmed under load.

---

## Operator Adaptation

Operators who want to run their own edgenode deployment for a different hApp can:

1. Copy the `deploy/` directory into their project (or reference it as a submodule)
2. Replace `mewsfeed-config.json.example` with their own hApp config
3. Set their own values in `staging.tfvars` / `production.tfvars` (project name, region, VM count, domain)
4. Supply secrets via their own `.env.*` files

The Ansible roles are hApp-agnostic — `install_happ` reads from the config file, so no role changes are needed to switch hApps.
