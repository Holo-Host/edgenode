#!/usr/bin/env bash
#
# Provision or update a deployment.
#
# Usage:
#   ./deploy/scripts/apply.sh <org> <env> [--dry-run] [tofu options]
#
# Examples:
#   source deploy/.env.acme-staging
#   ./deploy/scripts/apply.sh acme staging
#
#   ./deploy/scripts/apply.sh acme staging --dry-run
#
# The script expects:
#   deploy/.env.<org>-<env>        — sourced before calling (sets TF_VAR_*)
#   deploy/tofu/<org>-<env>.tfvars — non-secret deployment config
#
# OpenTofu state is isolated per deployment using workspaces.
# State is stored in deploy/tofu/terraform.tfstate.d/<org>-<env>/.
#
set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <org> <env> [--dry-run] [tofu options]" >&2
  exit 1
fi

ORG="$1"; shift
ENV="$1"; shift
DEPLOYMENT="$ORG-$ENV"

DRY_RUN=false
TOFU_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) TOFU_ARGS+=("$arg") ;;
  esac
done

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/.."
TOFU_DIR="$DEPLOY_DIR/tofu"
DIST_DIR="$DEPLOY_DIR/dist"
LOG_COLLECTOR_DIR="$DEPLOY_DIR/../docker/log-collector"
TFVARS="$TOFU_DIR/$DEPLOYMENT.tfvars"

log()  { echo -e "\033[0;32m[$DEPLOYMENT]\033[0m $*"; }
err()  { echo -e "\033[0;31m[$DEPLOYMENT]\033[0m $*" >&2; }

# ── Validate env ──────────────────────────────────────────────────────────────

for var in TF_VAR_hcloud_token TF_VAR_cloudflare_api_token TF_VAR_cloudflare_account_id; do
  if [[ -z "${!var:-}" ]]; then
    err "$var is not set. Did you source deploy/.env.$DEPLOYMENT?"
    exit 1
  fi
done

if [[ ! -f "$TFVARS" ]]; then
  err "tfvars not found: $TFVARS"
  err "Copy deploy/tofu/example.tfvars to $TFVARS and fill in the values."
  exit 1
fi

# ── Build log-collector Worker bundle ─────────────────────────────────────────

log "Building log-collector Worker..."

if [[ ! -d "$LOG_COLLECTOR_DIR" ]]; then
  err "log-collector source not found at: $LOG_COLLECTOR_DIR"
  exit 1
fi

if [[ ! -d "$LOG_COLLECTOR_DIR/node_modules" ]]; then
  log "Installing log-collector dependencies..."
  (cd "$LOG_COLLECTOR_DIR" && npm install)
fi

mkdir -p "$DIST_DIR"
NODE_PATH="$LOG_COLLECTOR_DIR/node_modules" npx esbuild \
  "$LOG_COLLECTOR_DIR/src/index.ts" \
  --bundle \
  --format=esm \
  --platform=browser \
  --outfile="$DIST_DIR/log-collector.js" \
  --external:__STATIC_CONTENT_MANIFEST \
  --external:"node:*" \
  --external:buffer \
  --log-level=warning

log "Built: $DIST_DIR/log-collector.js ($(wc -c < "$DIST_DIR/log-collector.js") bytes)"

# ── OpenTofu ──────────────────────────────────────────────────────────────────

cd "$TOFU_DIR"

log "Initialising OpenTofu..."
tofu init -reconfigure

# Select (or create) the workspace for this deployment
if tofu workspace list | grep -qE "^\*?\s+$DEPLOYMENT$"; then
  tofu workspace select "$DEPLOYMENT"
else
  log "Creating workspace '$DEPLOYMENT'..."
  tofu workspace new "$DEPLOYMENT"
fi

if $DRY_RUN; then
  log "Dry run — running tofu plan..."
  tofu plan -var-file="$TFVARS" "${TOFU_ARGS[@]}"
else
  log "Applying deployment '$DEPLOYMENT'..."
  tofu apply -var-file="$TFVARS" "${TOFU_ARGS[@]}"

  log ""
  log "Deployment complete. Outputs:"
  tofu output
  log ""
  log "Next: run deploy/scripts/bootstrap-harvester.sh to install the Unyt hApp on the harvester."
fi
