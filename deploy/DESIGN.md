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
  → h2hc-linker               (systemd, on edgenode VM)
  → cloudflared tunnel        (systemd, on edgenode VM)
  → edgenode container        (Holochain conductor, hApp installed via install_happ)
       ↓ log-sender
  → Cloudflare Worker         (log-collector, KV-backed)
       ↓ polled by
  → edgenode-harvester        (log-harvester → Unyt invoices)
```

### Hetzner VMs

| Role | Image | Notes |
|------|-------|-------|
| `edgenode` | `ghcr.io/holo-host/edgenode` | Holochain conductor + log-sender + h2hc-linker + cloudflared |
| `harvester` | `ghcr.io/holo-host/edgenode-harvester` | log-harvester, polls log-collector, generates Unyt invoices |

One or more edgenode VMs can be deployed; the joining service registers all of them in Cloudflare KV.

### Cloudflare Resources

| Resource | Purpose |
|----------|---------|
| Pages project | Hosts the UI build and `.happ` bundle |
| Worker: joining service | Authorises HWC browser nodes via invite code, stores sessions in KV |
| Worker: log-collector | Receives log-sender reports from edgenode(s), stores in KV |
| KV namespace: `SESSIONS` | Shared by joining service (sessions, linker registrations) |
| KV namespace: `LOGS` | Used by log-collector |

---

## Tooling

### Why OpenTofu + Ansible

The deployment has two distinct concerns:

**Cloud resource provisioning** (Cloudflare, Hetzner VMs): declarative, stateful, idempotent. OpenTofu (Terraform-compatible) handles this well. The Cloudflare and Hetzner Cloud providers are both mature.

**Container and service management** (edgenode, harvester, h2hc-linker, cloudflared): imperative configuration of remote hosts. Ansible is agentless, idempotent, and straightforward to read for operators who are not infrastructure specialists.

Shell scripts are appropriate for local dev but are too fragile for multi-host, multi-environment deployments — no state management, no rollback, poor idempotency guarantees.

### Why Hetzner

- Lower cost per VM than DigitalOcean for always-on nodes that are largely idle
- EU datacenter locations suit the expected user base
- `hetznercloud/hcloud` Terraform provider is mature and well-maintained
- `cx22` (2 vCPU, 4 GB RAM) is sufficient for an edgenode running one hApp

---

## Secrets and Configuration

All secrets are passed as environment variables. This matches the pattern established in `mewsfeed/deploy/deploy.sh` and the edgenode container's own env-var-based configuration (`LOG_SENDER_ENDPOINT`, `LOG_SENDER_UNYT_PUB_KEY`, etc.).

Secrets are never committed. Operators copy `.env.example` to `.env.staging` or `.env.production`, fill in their values, and source the file before running any tooling.

```bash
cp deploy/.env.example deploy/.env.staging
# edit .env.staging
source deploy/.env.staging
make staging
```

OpenTofu reads secrets via `TF_VAR_*` prefixed variables. Ansible reads them from the environment via `lookup('env', ...)`.

### Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `HCLOUD_TOKEN` | OpenTofu | Hetzner Cloud API token |
| `CLOUDFLARE_ACCOUNT_ID` | OpenTofu, wrangler | Cloudflare account ID |
| `CLOUDFLARE_API_TOKEN` | OpenTofu, wrangler | Cloudflare API token (Workers, Pages, KV) |
| `CLOUDFLARE_WORKERS_SUBDOMAIN` | OpenTofu | Workers subdomain (e.g. `myaccount`) |
| `LINKER_ADMIN_SECRET` | Ansible, joining service | Shared secret between linker and joining service |
| `INVITE_CODES` | OpenTofu / joining service | Comma-separated invite codes |
| `LOG_SENDER_ENDPOINT` | Ansible → edgenode | Log-collector URL |
| `LOG_SENDER_UNYT_PUB_KEY` | Ansible → edgenode | Unyt agent public key |
| `LAIR_PASSWORD` | Ansible → edgenode | Lair keystore password |
| `COLLECTOR_URL` | Ansible → harvester | Log-collector URL |
| `ADMIN_SECRET` | Ansible → harvester | Log-collector admin secret |
| `SSH_KEY_PATH` | Ansible | Path to SSH private key for Hetzner VMs |

---

## Directory Structure

```
deploy/
  DESIGN.md                    # This document
  .env.example                 # Template for all secrets (committed)
  Makefile                     # make staging / make production / make status / make destroy

  tofu/
    cloudflare.tf              # Pages, joining service Worker, log-collector Worker, KV namespaces
    hetzner.tf                 # Hetzner VMs (edgenode, harvester), SSH key, firewall
    variables.tf               # All input variables with descriptions
    outputs.tf                 # VM IPs, Worker URLs, KV namespace IDs
    staging.tfvars             # Non-secret staging config (committed)
    production.tfvars          # Non-secret production config (committed)

  ansible/
    inventory/
      staging.yml              # Populated from `tofu output` via Makefile
      production.yml
    roles/
      edgenode/                # docker pull, docker run with env vars, install_happ
      harvester/               # docker pull, docker run with env vars
      linker/                  # download h2hc-linker binary, write systemd unit
      tunnel/                  # install cloudflared, write systemd unit
    site.yml                   # Top-level playbook: edgenode → linker → tunnel → harvester

  mewsfeed-config.json.example # hApp config template for operators using mewsfeed
```

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
make staging-apply   # tofu apply -var-file=staging.tfvars → creates VMs + Cloudflare resources

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

1. **Number of edgenode VMs**: The design supports N edgnode VMs. For staging, 2 is the minimum for meaningful DHT arc coverage (matching `NUM_CONDUCTORS=2` in the current `deploy.sh`). Production may warrant more.

2. **cloudflared tunnel vs named tunnel**: Quick tunnels (anonymous, URL rotates) are used in `deploy.sh`. Named tunnels (authenticated, stable URL) are more appropriate for production — the linker URL would not change across restarts. This affects whether `seed-kv` is needed after tunnel restarts.

3. **log-collector deployment**: The log-collector is a Cloudflare Worker (see `docker/log-collector/wrangler.toml`). It can be deployed via the Cloudflare Terraform provider alongside the joining service Worker, or kept as a separate `wrangler deploy` step. The former is cleaner for IaC but requires the Cloudflare provider to support Worker deployments with KV bindings (it does, via `cloudflare_worker_script`).

4. **Harvester VM sizing**: The harvester runs `edgenode-harvester` which has lighter Holochain requirements than the standard edgenode. A `cx11` (2 vCPU, 2 GB) may be sufficient; this should be confirmed under load.

5. **State backend for OpenTofu**: For a single operator, local state is acceptable. For team use (staging managed by multiple people), a remote state backend (e.g. Cloudflare R2 or Hetzner Object Storage) should be configured.

---

## Operator Adaptation

Operators who want to run their own edgenode deployment for a different hApp can:

1. Copy the `deploy/` directory into their project (or reference it as a submodule)
2. Replace `mewsfeed-config.json.example` with their own hApp config
3. Set their own values in `staging.tfvars` / `production.tfvars` (project name, region, VM count)
4. Supply secrets via their own `.env.*` files

The Ansible roles are hApp-agnostic — `install_happ` reads from the config file, so no role changes are needed to switch hApps.
