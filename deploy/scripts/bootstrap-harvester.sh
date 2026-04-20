#!/usr/bin/env bash
#
# One-time harvester bootstrap: installs the Unyt hApp on the harvester
# conductor and registers the agent key with the joining service.
#
# Run this AFTER `tofu apply` has provisioned the harvester VM and the
# conductor container has had time to start (~1-2 minutes).
#
# Prerequisites:
#   source deploy/.env.staging          # or .env.production
#   wrangler authenticated              # wrangler whoami
#   docker available in PATH
#   jq available in PATH
#
# Required env vars (set via .env.*):
#   SSH_PUBLIC_KEY                      # used by tofu — SSH key must be added to agent
#   HARVESTER_NETWORK_SEED              # network seed for the Unyt hApp cell
#   JOINING_SERVICE_CONFIG_PATH         # path to joining-config.json
#   JOINING_SERVICE_DEPLOY_SCRIPT       # path to the joining service deploy.sh
#
# Optional env vars:
#   BOOTSTRAP_IMAGE                     # override bootstrap container image
#   HARVESTER_ADMIN_PORT                # override conductor admin port (default: 4444)
#   SSH_USER                            # SSH user on harvester VM (default: root)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOFU_DIR="$SCRIPT_DIR/../tofu"
BOOTSTRAP_IMAGE="${BOOTSTRAP_IMAGE:-ghcr.io/holo-host/edgenode-bootstrap:latest}"
HARVESTER_ADMIN_PORT="${HARVESTER_ADMIN_PORT:-4444}"
LOCAL_TUNNEL_PORT="${LOCAL_TUNNEL_PORT:-14444}"
SSH_USER="${SSH_USER:-root}"

log()  { echo -e "\033[0;32m[bootstrap]\033[0m $*"; }
warn() { echo -e "\033[0;33m[bootstrap]\033[0m $*"; }
err()  { echo -e "\033[0;31m[bootstrap]\033[0m $*" >&2; }

# ── Validate env ─────────────────────────────────────────────────────────────

for var in HARVESTER_NETWORK_SEED JOINING_SERVICE_CONFIG_PATH JOINING_SERVICE_DEPLOY_SCRIPT; do
  if [[ -z "${!var:-}" ]]; then
    err "$var is not set. Did you source deploy/.env.staging?"
    exit 1
  fi
done

if [[ ! -f "$JOINING_SERVICE_CONFIG_PATH" ]]; then
  err "JOINING_SERVICE_CONFIG_PATH not found: $JOINING_SERVICE_CONFIG_PATH"
  exit 1
fi

if [[ ! -f "$JOINING_SERVICE_DEPLOY_SCRIPT" ]]; then
  err "JOINING_SERVICE_DEPLOY_SCRIPT not found: $JOINING_SERVICE_DEPLOY_SCRIPT"
  exit 1
fi

# ── Get harvester IP from tofu output ────────────────────────────────────────

log "Reading harvester IP from tofu output..."
HARVESTER_IP=$(cd "$TOFU_DIR" && tofu output -raw harvester_ip)
if [[ -z "$HARVESTER_IP" ]]; then
  err "Could not read harvester_ip from tofu output. Has tofu apply been run?"
  exit 1
fi
log "Harvester IP: $HARVESTER_IP"

# ── SSH tunnel ────────────────────────────────────────────────────────────────

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
TUNNEL_PID=""

cleanup() {
  if [[ -n "$TUNNEL_PID" ]] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    log "Closing SSH tunnel (pid $TUNNEL_PID)..."
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log "Opening SSH tunnel (local:$LOCAL_TUNNEL_PORT -> remote:$HARVESTER_ADMIN_PORT)..."
# shellcheck disable=SC2086
ssh $SSH_OPTS -N \
  -L "${LOCAL_TUNNEL_PORT}:localhost:${HARVESTER_ADMIN_PORT}" \
  "${SSH_USER}@${HARVESTER_IP}" &
TUNNEL_PID=$!

for i in $(seq 1 10); do
  nc -z localhost "$LOCAL_TUNNEL_PORT" 2>/dev/null && break
  [[ "$i" -eq 10 ]] && { err "SSH tunnel failed to open within 10 seconds"; exit 1; }
  sleep 1
done
log "SSH tunnel ready (pid $TUNNEL_PID)"

# ── Run bootstrap container ───────────────────────────────────────────────────

log "Running bootstrap container..."
INSTALL_RESULT=$(docker run --rm \
  --network host \
  -e HC_ADMIN_WS="ws://localhost:${LOCAL_TUNNEL_PORT}" \
  -e APP_ID="edgenode-harvester" \
  -e NETWORK_SEED="$HARVESTER_NETWORK_SEED" \
  "$BOOTSTRAP_IMAGE")

AGENT_KEY=$(echo "$INSTALL_RESULT" | jq -r '.agent_key')
if [[ -z "$AGENT_KEY" || "$AGENT_KEY" == "null" ]]; then
  err "Bootstrap container did not return an agent key"
  err "Output: $INSTALL_RESULT"
  exit 1
fi
log "Agent key: $AGENT_KEY"

# ── Update joining service config ─────────────────────────────────────────────

log "Updating joining service config..."
TMP_CONFIG=$(mktemp)
jq --arg key "$AGENT_KEY" '
  .allowed_agents = ((.allowed_agents // []) + [$key] | unique) |
  .auth_methods = (
    [.auth_methods[] |
      if . == "agent_allow_list" then
        empty
      elif type == "string" then
        { any_of: [., "agent_allow_list"] }
      elif type == "object" and .any_of then
        .any_of = (.any_of + ["agent_allow_list"] | unique)
      else .
      end
    ] |
    if length == 0 then ["agent_allow_list"] else . end
  )
' "$JOINING_SERVICE_CONFIG_PATH" > "$TMP_CONFIG"

mv "$TMP_CONFIG" "$JOINING_SERVICE_CONFIG_PATH"
log "Updated: $(jq -r '.allowed_agents | length' "$JOINING_SERVICE_CONFIG_PATH") allowed agent(s)"

log "Redeploying joining service..."
DEPLOY_ARGS=("deploy" "--config-file" "$JOINING_SERVICE_CONFIG_PATH")
if [[ -n "${JOINING_SERVICE_SIGNING_KEY_FILE:-}" && -f "$JOINING_SERVICE_SIGNING_KEY_FILE" ]]; then
  DEPLOY_ARGS+=("--signing-key-file" "$JOINING_SERVICE_SIGNING_KEY_FILE")
fi
bash "$JOINING_SERVICE_DEPLOY_SCRIPT" "${DEPLOY_ARGS[@]}"

log "Waiting 5s for Cloudflare propagation..."
sleep 5

# ── Save results ──────────────────────────────────────────────────────────────

RESULTS_DIR="$SCRIPT_DIR/../results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/bootstrap-result.json"

echo "$INSTALL_RESULT" | jq \
  --arg ip "$HARVESTER_IP" \
  --arg bootstrapped_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '. + { server_ip: $ip, bootstrapped_at: $bootstrapped_at }' \
  > "$RESULTS_FILE"

HISTORY_DIR="$RESULTS_DIR/history"
mkdir -p "$HISTORY_DIR"
cp "$RESULTS_FILE" "$HISTORY_DIR/bootstrap-result-$(date +%Y%m%d-%H%M%S).json"

log ""
log "========================================="
log "  Bootstrap Complete"
log "========================================="
log ""
log "Harvester: ${SSH_USER}@${HARVESTER_IP}"
log "Agent Key: $AGENT_KEY"
log "Results:   $RESULTS_FILE"
log ""
