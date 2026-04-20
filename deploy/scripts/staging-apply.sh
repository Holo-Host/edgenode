#!/usr/bin/env bash
#
# Build and deploy the staging environment.
#
# Prerequisites:
#   source deploy/.env.staging   # sets TF_VAR_* and other env vars
#   npm / npx available in PATH  # for esbuild (log-collector bundle)
#   tofu available in PATH       # OpenTofu CLI
#
# Usage:
#   source deploy/.env.staging
#   ./deploy/scripts/staging-apply.sh [tofu options]
#
# Any extra arguments are forwarded to `tofu apply`.
# To preview changes without applying: pass --dry-run (maps to `tofu plan`).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/.."
TOFU_DIR="$DEPLOY_DIR/tofu"
DIST_DIR="$DEPLOY_DIR/dist"
LOG_COLLECTOR_DIR="$DEPLOY_DIR/../docker/log-collector"

DRY_RUN=false
TOFU_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) TOFU_ARGS+=("$arg") ;;
  esac
done

log()  { echo -e "\033[0;32m[staging]\033[0m $*"; }
err()  { echo -e "\033[0;31m[staging]\033[0m $*" >&2; }

# ── Validate env ─────────────────────────────────────────────────────────────

for var in TF_VAR_hcloud_token TF_VAR_cloudflare_api_token TF_VAR_cloudflare_account_id; do
  if [[ -z "${!var:-}" ]]; then
    err "$var is not set. Did you source deploy/.env.staging?"
    exit 1
  fi
done

# ── Build log-collector Worker bundle ────────────────────────────────────────

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

if $DRY_RUN; then
  log "Dry run — running tofu plan..."
  tofu plan -var-file=staging.tfvars "${TOFU_ARGS[@]}"
else
  log "Applying staging environment..."
  tofu apply -var-file=staging.tfvars "${TOFU_ARGS[@]}"

  log ""
  log "Deployment complete. Outputs:"
  tofu output
  log ""
  log "Next: run deploy/scripts/bootstrap-harvester.sh to install the Unyt hApp on the harvester."
fi
