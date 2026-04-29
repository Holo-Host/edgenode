# Deployment Guide: Hetzner + Cloudflare

Step-by-step guide for provisioning and operating a Hetzner + Cloudflare
edgenode deployment using the OpenTofu IaC in `deploy/tofu/` and the
`hdeploy` CLI from `Holo-Host/platform-automation`.

For context on architecture, design decisions, and disaster recovery, see
[DESIGN.md](DESIGN.md). For other deployment paths (pure Cloudflare, Docker
Compose), see [DESIGN.md — Appendix C](DESIGN.md#appendix-c-deployment-path-options).

---

## Naming Convention

Each deployment is identified by `<org>-<env>`, where:

- `<org>` — a short slug for the organisation operating the stack (assigned by Holo)
- `<env>` — environment tier: `staging` or `prod`

Examples: `acme-staging`, `acme-prod`, `junto-staging`.

This identifier prefixes all cloud resources (Hetzner VMs, Cloudflare Workers,
DNS records) and is used as the OpenTofu workspace name for state isolation.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [OpenTofu](https://opentofu.org/docs/intro/install/) (`tofu`) | Provision Hetzner and Cloudflare resources |
| [hdeploy](https://github.com/Holo-Host/platform-automation) | Holo platform operations CLI |
| [Docker](https://docs.docker.com/get-docker/) | Run the harvester bootstrap container |
| [wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/) | Deploy the joining service Worker |
| SSH key pair | Access to Hetzner VMs and harvester bootstrap |

Accounts required: **Hetzner Cloud**, **Cloudflare** (Workers + DNS).

---

## First-Time Setup

### 1. Populate secrets

```bash
cp deploy/.env.example deploy/.env.acme-staging
$EDITOR deploy/.env.acme-staging
```

Fill in all values. The file is self-documenting. Key items:

- `HCLOUD_TOKEN` — create at [Hetzner Cloud console](https://console.hetzner.cloud/) → Security → API Tokens
- `CLOUDFLARE_API_TOKEN` — create at Cloudflare → My Profile → API Tokens with permissions: Workers Scripts: Edit, Workers KV Storage: Edit, DNS: Edit, Account Settings: Read
- `SSH_PUBLIC_KEY` — contents of your SSH public key (e.g. `cat ~/.ssh/id_ed25519.pub`)

### 2. Create deployment tfvars

Copy the example and fill in the values for this deployment:

```bash
cp deploy/tofu/example.tfvars deploy/tofu/acme-staging.tfvars
$EDITOR deploy/tofu/acme-staging.tfvars
```

Set `project_name = "acme-staging"` and replace the placeholder domain. All
other values are reasonable defaults (2 × `cx22` edgenodes + 1 × `cx22`
harvester, `nbg1` region, 10 GB volumes).

### 3. Configure your DNS zone

The `CLOUDFLARE_ZONE_ID` in `.env.acme-staging` must match the zone that owns
the domain set in `acme-staging.tfvars`. OpenTofu creates
`linker-0.<domain>` and `linker-1.<domain>` as DNS A records pointing at the
edgenode VM IPs.

Ensure the Cloudflare API token has **DNS: Edit** permission on that zone.

---

## Provisioning

```bash
source deploy/.env.acme-staging
hdeploy provision --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --log-collector-src docker/log-collector
```

This command:
1. Builds the log-collector Worker bundle (esbuild via the log-collector's own toolchain)
2. Selects (or creates) the `acme-staging` OpenTofu workspace
3. Runs `tofu init` + `tofu apply` with `acme-staging.tfvars`

OpenTofu provisions in dependency order:
- Cloudflare: KV namespaces → log-collector Worker → DNS records (after VMs)
- Hetzner: SSH key → firewalls → volumes → VMs → volume attachments

Each VM runs cloud-init on first boot: installs Docker, waits for the volume
device, formats and mounts it at `/data`, pulls the container image, starts
the container.

**Expected duration:** ~3-5 minutes for VMs to boot and cloud-init to complete.

### Preview changes without applying

```bash
source deploy/.env.acme-staging
hdeploy provision --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --dry-run
```

### Verify containers are running

```bash
# Check edgenode container logs
EDGENODE_IP=$(cd deploy/tofu && tofu output -json edgenode_ips | jq -r '.[0]')
ssh root@$EDGENODE_IP docker logs edgenode --tail 50

# Check harvester container logs
HARVESTER_IP=$(cd deploy/tofu && tofu output -raw harvester_ip)
ssh root@$HARVESTER_IP docker logs harvester --tail 50
```

---

## Initialise the Deployment

After provisioning, generate the network seed and joining key for this deployment:

```bash
source deploy/.env.acme-staging
hdeploy init-deployment --deployment acme-staging --tofu-dir deploy/tofu
```

This writes `network_seed` and `joining_key_pub` to the deployment KV namespace.
Run once per deployment — it is idempotent and will refuse to overwrite an
existing seed.

---

## Deploy the Joining Service

```bash
source deploy/.env.acme-staging
hdeploy deploy-joining-service --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --joining-service-dir ../joining-service
```

This deploys the joining service Worker via wrangler and writes
`linker_registrations` to the sessions KV namespace. Safe to re-run after
infrastructure changes that affect linker URLs.

---

## Bootstrap the Harvester

The harvester conductor starts on first boot but the Unyt hApp is not yet
installed. Run the bootstrap after the conductor is ready (~1-2 minutes after
provisioning):

```bash
source deploy/.env.acme-staging
hdeploy bootstrap-harvester --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --bootstrap-image ghcr.io/holo-host/bootstrap:latest
```

This command:
1. Reads the harvester IP from `tofu output`
2. Opens an SSH tunnel to the conductor admin port
3. Runs the bootstrap container to generate an agent key and install the Unyt hApp
4. Writes `bootstrap_result` and `harvester_ip` to the deployment KV namespace

**Bootstrap is a one-time operation.** The agent key is stable for the
lifetime of the persistent volume. Do not re-run bootstrap unless you have
intentionally wiped the volume.

---

## Subsequent Operations

### Config or infrastructure changes

```bash
source deploy/.env.acme-staging
hdeploy provision --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --log-collector-src docker/log-collector
```

OpenTofu is idempotent — it only changes resources that differ from the
current state.

### Container image update (edgenode or harvester)

Replace the VM. OpenTofu detaches and reattaches the persistent volume to the
new VM; Holochain data is fully preserved.

```bash
source deploy/.env.acme-staging
cd deploy/tofu
tofu workspace select acme-staging

# Replace a specific edgenode VM (index 0 or 1)
tofu apply -replace=hcloud_server.edgenode[0] -var-file=acme-staging.tfvars

# Replace the harvester VM
tofu apply -replace=hcloud_server.harvester -var-file=acme-staging.tfvars
```

To deploy a specific image version rather than `latest`, update `acme-staging.tfvars`:

```hcl
edgenode_image  = "ghcr.io/holo-host/edgenode:v1.2.3"
harvester_image = "ghcr.io/holo-host/edgenode-harvester:v1.2.3"
```

### Joining service update

```bash
source deploy/.env.acme-staging
hdeploy deploy-joining-service --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --joining-service-dir ../joining-service
```

### Staging → production

```bash
cp deploy/.env.example deploy/.env.acme-prod
$EDITOR deploy/.env.acme-prod      # set production credentials and domain
cp deploy/tofu/example.tfvars deploy/tofu/acme-prod.tfvars
$EDITOR deploy/tofu/acme-prod.tfvars   # set project_name = "acme-prod", increase volume sizes
source deploy/.env.acme-prod

hdeploy provision --deployment acme-prod \
  --tofu-dir deploy/tofu \
  --log-collector-src docker/log-collector
hdeploy init-deployment --deployment acme-prod --tofu-dir deploy/tofu
hdeploy deploy-joining-service --deployment acme-prod \
  --tofu-dir deploy/tofu \
  --joining-service-dir ../joining-service
hdeploy bootstrap-harvester --deployment acme-prod \
  --tofu-dir deploy/tofu \
  --bootstrap-image ghcr.io/holo-host/bootstrap:latest
```

---

## Backup and Disaster Recovery

### Daily volume snapshots (recommended)

Hetzner volumes are snapshotted with the container stopped to ensure database
consistency. Set this up as a cron job on your operator machine or via Hetzner
API automation:

```bash
EDGENODE_IP=$(cd deploy/tofu && tofu output -json edgenode_ips | jq -r '.[0]')
VOLUME_ID=$(cd deploy/tofu && tofu output -json volume_ids | jq -r '.edgenode[0]')

ssh root@$EDGENODE_IP docker stop edgenode
hcloud volume create-snapshot "$VOLUME_ID" --description "edgenode-0-$(date +%Y%m%d)"
ssh root@$EDGENODE_IP docker start edgenode
```

Keep 7 daily snapshots. See [DESIGN.md — Disaster Recovery](DESIGN.md#disaster-recovery)
for recovery procedures.

### Recovery: VM failure, volume intact

The persistent volume survives independently. A normal `hdeploy provision`
recreates the VM and reattaches the volume. No data is lost; no bootstrap
re-run needed.

```bash
source deploy/.env.acme-staging
hdeploy provision --deployment acme-staging \
  --tofu-dir deploy/tofu \
  --log-collector-src docker/log-collector
```

---

## Teardown

```bash
source deploy/.env.acme-staging
cd deploy/tofu
tofu workspace select acme-staging
tofu destroy -var-file=acme-staging.tfvars
```

> **Warning:** This destroys VMs and their volumes. All Holochain data is lost
> unless you have snapshots. Cloudflare resources (KV namespaces, Worker,
> DNS records) are also removed.
