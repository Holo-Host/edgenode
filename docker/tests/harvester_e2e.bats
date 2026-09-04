#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# End-to-end pipeline test: edgenode (log-sender) -> log-collector -> edgenode-harvester
#
# Requires both edgenode and edgenode-harvester services to be running.
# Run via run_harvester_tests.sh which starts both services.

EDGENODE_SERVICE="edgenode"
HARVESTER_SERVICE="${SERVICE_NAME:-edgenode-harvester}"
ADMIN_SECRET="${ADMIN_SECRET:-test_admin_secret}"
# Match the docker-compose default so install_happ's DNA registration (which uses
# the startup log-sender config) aligns with the UNYT key on our test metrics.
UNYT_PUB_KEY="${LOG_SENDER_UNYT_PUB_KEY:-uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO}"
LOG_COLLECTOR_URL="http://log-collector:8787"
CONFIG_PATH="/data/log-harvester/config.json"

setup() {
  if ! docker compose ps "$EDGENODE_SERVICE" 2>/dev/null | grep -q "running\|Up"; then
    skip "edgenode service is not running"
  fi
  if ! docker compose ps "$HARVESTER_SERVICE" 2>/dev/null | grep -q "running\|Up"; then
    skip "edgenode-harvester service is not running"
  fi
}

@test "full pipeline: log-sender submits metrics that harvester fetches and invoices" {
  local E2E_CONFIG="/etc/log-sender/e2e_harvester_test.json"
  local E2E_LOG_DIR="/data/logs/e2e_harvester_test"

  # --- Setup: clean slate ---

  docker compose exec -T -u nonroot "$EDGENODE_SERVICE" rm -f "$E2E_CONFIG" 2>/dev/null || true
  docker compose exec -T "$HARVESTER_SERVICE" rm -f /data/e2e-harvest-config.json 2>/dev/null || true

  # Wipe all metrics and invoice periods so the harvester only processes the small
  # set of metrics we submit in this test — avoids paginating through hundreds of
  # metrics from the continuously running edgenode log-sender.
  docker compose exec -T log-collector \
    npx --yes wrangler d1 execute log-collector-db \
    --command="DELETE FROM metrics; DELETE FROM invoice_periods; DELETE FROM dna_registrations;" 2>/dev/null || true

  # --- Step 1: Submit real signed metrics via log-sender ---

  run docker compose exec -T -u nonroot "$EDGENODE_SERVICE" mkdir -p "$E2E_LOG_DIR"
  assert_success

  local current_time=$(( $(date +%s) * 1000000 ))
  run docker compose exec -T -u nonroot "$EDGENODE_SERVICE" \
    sh -c "echo '{\"k\":\"fetchedOps\",\"t\":\"${current_time}\",\"count\":5,\"latency\":50}' > ${E2E_LOG_DIR}/metrics.jsonl"
  assert_success

  run docker compose exec -T -u nonroot "$EDGENODE_SERVICE" log-sender init \
    --config-file "$E2E_CONFIG" \
    --endpoint "$LOG_COLLECTOR_URL" \
    --unyt-pub-key "$UNYT_PUB_KEY" \
    --report-path "$E2E_LOG_DIR/" \
    --conductor-config-path /etc/holochain/conductor-config.yaml \
    --report-interval-seconds 2
  assert_success

  # install_happ registers the ziptest DNA in the log-collector under the startup
  # log-sender config's drone (which uses UNYT_PUB_KEY = uhCAkDM-...).
  # This populates dna_registrations so get-registered-dna succeeds for that UNYT key.
  local ziptest_json="${SCRIPT_DIR:-${BATS_TEST_DIRNAME}/..}/ziptest.json"
  docker compose cp "$ziptest_json" "${EDGENODE_SERVICE}:/home/nonroot/"
  run docker compose exec -T -u nonroot "$EDGENODE_SERVICE" \
    sh -c 'cd /home/nonroot && install_happ ziptest.json test-node'
  assert_success

  run docker compose exec -T -u nonroot "$EDGENODE_SERVICE" \
    timeout 25 log-sender service --config-file "$E2E_CONFIG"
  # timeout exit is expected; what matters is that metrics were submitted

  # --- Step 2: Verify fresh metrics reached D1 ---

  local count
  count=$(docker compose exec -T log-collector \
    npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null \
    | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")

  [[ "$count" -gt 0 ]] || fail "No new metrics found in D1 after log-sender run (count=$count)"

  # --- Step 3: Run harvester one-shot against the fresh data ---

  # Copy config with lastInvoice=0 to bypass the 24h gate and avoid the lockfile
  # held by the running service.
  run docker compose exec -T "$HARVESTER_SERVICE" \
    sh -c "jq '.lastInvoice = 0' ${CONFIG_PATH} > /data/e2e-harvest-config.json && chown nonroot:nonroot /data/e2e-harvest-config.json"
  assert_success

  # --today      : query today's UTC range (covers our freshly submitted metrics)
  # --dry-run    : skip the Holochain create_parked_spend call; still calls
  #               get-registered-dna and prints "Successfully invoiced logs."
  run docker compose exec -T "$HARVESTER_SERVICE" \
    gosu nonroot node /app/dist/log-harvester.js exec \
      --config /data/e2e-harvest-config.json \
      --today \
      --dry-run
  assert_success

  # --- Step 4: Assert the full pipeline completed end-to-end ---

  # Harvester fetched at least one metric from log-collector
  assert_output --partial '"fetched metrics count"'
  echo "$output" | grep '"fetched metrics count"' | grep -qv ',0\]'

  # Harvester resolved the full invoice cycle (dry-run path skips Holochain call)
  assert_output --partial '"Successfully invoiced logs."'
}
