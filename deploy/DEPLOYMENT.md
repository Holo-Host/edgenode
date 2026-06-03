# Deployment Guide: Hetzner + Cloudflare

Step-by-step guide for provisioning and operating a Hetzner + Cloudflare
edgenode deployment using the OpenTofu IaC in `deploy/tofu/` and the
`hdeploy` CLI from `Holo-Host/platform-automation`.

For context on architecture, design decisions, and disaster recovery, see
[DESIGN.md](DESIGN.md). For other deployment paths (pure Cloudflare, Docker
Compose), see [DESIGN.md — Appendix C](DESIGN.md#appendix-c-deployment-path-options).

---

## Deployment Model

### One stack per hApp

Due to the h2hc-linker constraint (the linker is network-specific), each hApp
deployment requires its own independent infrastructure stack: dedicated edgenode
VMs, harvester, log-collector Worker, and joining service Worker. A steward
running multiple hApps has multiple independent stacks, all within the same
Hetzner project and Cloudflare zone.

### Two deployment workflows

**happ-publisher-ui (primary workflow):** Stewards use
`Holo-Host/happ-publisher-ui` to generate a command plan for their hApp. A Holo
operator executes the generated commands. This is the intended workflow for all
steward-initiated deployments.

**Manual operator workflow:** Holo operators can run `hdeploy` commands directly,
following this document. This is used for platform maintenance, debugging, and
initial testing before the UI workflow is validated.

The commands are identical — `happ-publisher-ui` generates the same `hdeploy`
command sequences documented here.

### deploy-joining-service: two modes

`hdeploy deploy-joining-service` operates in two modes:

| Mode | When `--joining-service-dir` is… | What happens |
|------|----------------------------------|--------------|
| **Full** | Provided | Deploys the Cloudflare Worker via wrangler, then writes joining config to sessions KV |
| **Config-only** | Omitted | Writes joining config to sessions KV only — Worker already running |

Use the **full mode** for first deployment and reactivation (`deploy`,
`reactivate` actions in happ-publisher-ui). Use **config-only mode** for
subsequent config changes (`create_app`, `modify_app`, `deactivate` — these
push a new joining config to KV; the Worker remains running).

### Assumptions

These assumptions underpin all deployment operations. Violating the irreversible
ones requires a full network rebuild.

| Assumption | Basis | Consequence if violated |
|---|---|---|
| One deployment = one hApp | h2hc-linker is network-specific | Multiple hApps cannot share a linker or infrastructure stack |
| `network_seed` is immutable after bootstrap | Holochain protocol | Changing it orphans all nodes; full rebuild required |
| `joining_server_signer` is immutable after bootstrap | Embedded in DNA at install time | Changing it orphans all nodes; full rebuild required |
| `JOINING_SERVICE_DIR` points to a checked-out `joining-service` repo | Required by wrangler | First deployment and reactivation fail without it |
| `BOOTSTRAP_IMAGE` resolves to a working bootstrap container | Required by all bootstrap operations | `bootstrap-harvester` and `bootstrap-edgenode` fail |
| The Holochain conductor is multi-hApp | Verified from Holochain source | Not a risk; documents why bootstrap is per-hApp, not per-conductor |

---

## Naming Convention

Each deployment is currently identified by `<steward>-<env>`, where:

- `<steward>` — a short slug for the steward operating the stack (assigned by Holo)
- `<env>` — environment tier: `staging` or `production`

Examples: `acme-staging`, `acme-production`, `junto-staging`.

This identifier prefixes all cloud resources (Hetzner VMs, Cloudflare Workers,
DNS records) and is used as the OpenTofu workspace name for state isolation.

> **Future:** Before running multiple hApps per steward or moving to production,
> names will transition to the three-segment form `<steward>-<happ>-<env>`
> (e.g. `acme-mewsfeed-staging`, `acme-mewsfeed-production`). The CLI, schemas,
> and env files will be updated at that point — see
> `platform-automation/docs/multi-tenancy.md` for the target design.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [OpenTofu](https://opentofu.org/docs/intro/install/) (`tofu`) | Provision Hetzner and Cloudflare resources |
| [hdeploy](https://github.com/Holo-Host/platform-automation) | Holo platform operations CLI |
| [Docker](https://docs.docker.com/get-docker/) | Run the harvester and edgenode bootstrap containers |
| [wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/) | Deploy the joining service Worker (first deployment only) |
| SSH key pair | Access to Hetzner VMs |

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
- `TOFU_DIR` — **absolute** path to `deploy/tofu` in the edgenode repo (e.g. `export TOFU_DIR="$(pwd)/deploy/tofu"`); must be absolute — `hdeploy` runs from `../platform-automation` and relative paths will not resolve
- `JOINING_SERVICE_DIR` — path to a local checkout of `Holo-Host/joining-service` (required for first deployment)
- `BOOTSTRAP_IMAGE` — bootstrap container image (e.g. `ghcr.io/holo-host/edgenode-bootstrap:latest`)

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

## happ-publisher-ui Workflow (Primary)

This is the intended workflow for steward-initiated deployments. A steward
generates a command plan in `Holo-Host/happ-publisher-ui`; a Holo operator
executes it. The commands are identical to the manual sequence below — the UI
just generates and sequences them.

### Step 1: Steward generates a plan

The steward opens `happ-publisher-ui`, fills in their hApp details, and triggers
the **deploy** action. The UI generates:

- A **command plan** — an ordered list of `hdeploy` commands to execute
- A **joining config JSON** — the joining service configuration for their hApp,
  at path `config/<deployment>/joining-service/joining-config.json` (relative to
  the `platform-automation` directory)

The steward sends the operator both artifacts (e.g. via copy-paste or a shared
file).

### Step 2: Operator sets up environment

Complete [First-Time Setup](#first-time-setup) if not already done. Then verify
these env vars are set in the deployment env file:

| Var | Purpose |
|-----|---------|
| `TOFU_DIR` | Path to `deploy/tofu` in the edgenode repo |
| `BOOTSTRAP_IMAGE` | Bootstrap container image reference |
| `JOINING_SERVICE_DIR` | Path to a local checkout of `Holo-Host/joining-service` |

```bash
# Source the env file for this deployment
source deploy/.env.acme-staging
```

### Step 3: Write the generated joining config

Create the directory and write the joining config JSON the steward provided:

```bash
mkdir -p ../platform-automation/config/acme-staging/joining-service
# Write or copy the steward-provided joining-config.json to:
# ../platform-automation/config/acme-staging/joining-service/joining-config.json
```

### Step 4: Execute the command plan

Run each command from the plan in order. All `hdeploy` commands run from the
`platform-automation` directory:

```bash
cd ../platform-automation

# Commands as generated by happ-publisher-ui for a deploy action.
# The deploy action provisions BOTH staging and production — 10 commands total.

# Staging (steps 1–5)
hdeploy provision -d acme-staging
hdeploy init-deployment -d acme-staging
hdeploy bootstrap-harvester -d acme-staging --bootstrap-image "$BOOTSTRAP_IMAGE"
hdeploy bootstrap-edgenode -d acme-staging --happ-url <happ-bundle-url> --bootstrap-image "$BOOTSTRAP_IMAGE"
hdeploy deploy-joining-service -d acme-staging \
  --joining-service-dir "$JOINING_SERVICE_DIR" \
  --joining-config config/acme-staging/joining-service/joining-config.json

# Production (steps 6–10)
hdeploy provision -d acme-production
hdeploy init-deployment -d acme-production
hdeploy bootstrap-harvester -d acme-production --bootstrap-image "$BOOTSTRAP_IMAGE"
hdeploy bootstrap-edgenode -d acme-production --happ-url <happ-bundle-url> --bootstrap-image "$BOOTSTRAP_IMAGE"
hdeploy deploy-joining-service -d acme-production \
  --joining-service-dir "$JOINING_SERVICE_DIR" \
  --joining-config config/acme-production/joining-service/joining-config.json
```

The UI generates these exact commands with the correct deployment name, hApp URL,
and config path. Run them in the order shown in the plan.

> **For subsequent config updates** (`create_app`, `modify_app`, `deactivate`
> actions), the plan generates only a `deploy-joining-service` command without
> `--joining-service-dir` — the Worker is already running and only the KV config
> changes.

---

## First Deployment (Manual Reference)

The following sequence provisions the full stack for a new hApp deployment. This
is the manual equivalent of `happ-publisher-ui`'s `deploy` action — the
generated commands are identical to these steps.

Commands below pass `--tofu-dir` and other flags explicitly for clarity.
Alternatively, set `TOFU_DIR`, `LOG_COLLECTOR_SRC`, `BOOTSTRAP_IMAGE`, and
`JOINING_SERVICE_DIR` in your env file and omit the flags — the CLI reads them
from the environment.

### 1. Provision infrastructure

```bash
source deploy/.env.acme-staging
hdeploy provision -d acme-staging \
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

#### Preview changes without applying

```bash
source deploy/.env.acme-staging
hdeploy provision -d acme-staging \
  --tofu-dir deploy/tofu \
  --dry-run
```

#### Verify containers are running

```bash
# Check edgenode container logs
EDGENODE_IP=$(cd deploy/tofu && tofu output -json edgenode_ips | jq -r '.[0]')
ssh root@$EDGENODE_IP docker logs edgenode --tail 50

# Check harvester container logs
HARVESTER_IP=$(cd deploy/tofu && tofu output -raw harvester_ip)
ssh root@$HARVESTER_IP docker logs harvester --tail 50
```

### 2. Initialise the deployment

Generate the network seed and joining key for this hApp deployment:

```bash
source deploy/.env.acme-staging
hdeploy init-deployment -d acme-staging --tofu-dir deploy/tofu
```

This writes `network_seed` and `joining_key_pub` to the deployment KV namespace.
**Run once per deployment — it fails if a seed already exists to prevent
accidental overwrite.** The network seed is immutable: changing it after
bootstrap orphans all nodes on the network. To restore a known seed after data
loss, use `hdeploy use-network-seed`.

### 3. Bootstrap the harvester

```bash
source deploy/.env.acme-staging
hdeploy bootstrap-harvester -d acme-staging \
  --tofu-dir deploy/tofu \
  --bootstrap-image "$BOOTSTRAP_IMAGE"
```

This command:
1. Reads the harvester IP from `tofu output`
2. Opens an SSH tunnel to the conductor admin port
3. Runs the bootstrap container to generate an agent key and install the Unyt hApp
4. Writes `bootstrap_result` and `harvester_ip` to the deployment KV namespace

**Bootstrap is a one-time operation.** The agent key is stable for the
lifetime of the persistent volume. Do not re-run bootstrap unless you have
intentionally wiped the volume.

### 4. Bootstrap the edgenodes

Install the steward's hApp on each edgenode conductor:

```bash
source deploy/.env.acme-staging
hdeploy bootstrap-edgenode -d acme-staging \
  --tofu-dir deploy/tofu \
  --happ-url https://github.com/GeekGene/mewsfeed/releases/download/v0.14.0/mewsfeed.webhapp \
  --bootstrap-image "$BOOTSTRAP_IMAGE"
```

Replace `--happ-url` with the `.webhapp` bundle URL for the steward's hApp.

**Bootstrap is a one-time operation** per edgenode volume. Do not re-run unless
you have intentionally wiped the volume.

### 5. Deploy the joining service

Copy and fill in `deploy/joining-service-config.example.json` for the hApp:

```bash
cp deploy/joining-service-config.example.json deploy/acme-joining-config.json
$EDITOR deploy/acme-joining-config.json
```

The config needs at minimum: `happ.id`, `happ.name`, `happ.happ_bundle_url`, and
`auth_methods`. See `joining-service-config.example.json` for membrane proof and
invite code variants.

`network_seed` and `linker_registrations` are injected automatically — do not set
them in the config file.

```bash
source deploy/.env.acme-staging
hdeploy deploy-joining-service -d acme-staging \
  --tofu-dir deploy/tofu \
  --joining-service-dir "$JOINING_SERVICE_DIR" \
  --joining-config deploy/acme-joining-config.json
```

This deploys the joining service Worker via wrangler and writes `joining_config`
(including the network seed from deployment KV and linker URLs from tofu outputs)
to the sessions KV namespace.

---

## Subsequent Operations

### hApp config update (create_app / modify_app)

When a steward updates their hApp configuration via `happ-publisher-ui`, the
generated plan only updates the joining service KV config — no infrastructure
changes and no Worker redeploy:

```bash
source deploy/.env.acme-staging
hdeploy deploy-joining-service -d acme-staging \
  --tofu-dir deploy/tofu \
  --joining-config deploy/acme-joining-config.json
```

Note the absence of `--joining-service-dir`: the Worker is already running and
only the KV config needs updating.

### Infrastructure or image changes

```bash
source deploy/.env.acme-staging
hdeploy provision -d acme-staging \
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

### Joining service Worker update

When Holo ships a new version of the joining service Worker, redeploy it:

```bash
source deploy/.env.acme-staging
hdeploy deploy-joining-service -d acme-staging \
  --tofu-dir deploy/tofu \
  --joining-service-dir "$JOINING_SERVICE_DIR" \
  --joining-config deploy/acme-joining-config.json
```

### Staging → production

```bash
cp deploy/.env.example deploy/.env.acme-production
$EDITOR deploy/.env.acme-production      # set production credentials and domain
cp deploy/tofu/example.tfvars deploy/tofu/acme-production.tfvars
$EDITOR deploy/tofu/acme-production.tfvars   # set project_name = "acme-production", increase volume sizes
source deploy/.env.acme-production

hdeploy provision -d acme-production \
  --tofu-dir deploy/tofu \
  --log-collector-src docker/log-collector
hdeploy init-deployment -d acme-production --tofu-dir deploy/tofu
hdeploy bootstrap-harvester -d acme-production \
  --tofu-dir deploy/tofu \
  --bootstrap-image "$BOOTSTRAP_IMAGE"
hdeploy bootstrap-edgenode -d acme-production \
  --tofu-dir deploy/tofu \
  --happ-url https://github.com/GeekGene/mewsfeed/releases/download/v0.14.0/mewsfeed.webhapp \
  --bootstrap-image "$BOOTSTRAP_IMAGE"
hdeploy deploy-joining-service -d acme-production \
  --tofu-dir deploy/tofu \
  --joining-service-dir "$JOINING_SERVICE_DIR" \
  --joining-config deploy/acme-joining-config.json
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
hdeploy provision -d acme-staging \
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
