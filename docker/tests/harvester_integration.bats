#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Lightweight connectivity checks: harvester container <-> log-collector.
# For the full end-to-end pipeline test see harvester_e2e.bats.

HARVESTER_SERVICE="${SERVICE_NAME:-edgenode-harvester}"
ADMIN_SECRET="${ADMIN_SECRET:-test_admin_secret}"

setup() {
  if ! docker compose ps "$HARVESTER_SERVICE" 2>/dev/null | grep -q "running\|Up"; then
    skip "edgenode-harvester service is not running"
  fi
}

@test "harvester network can reach log-collector" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    curl -sf http://log-collector:8787/
  assert_success
}

@test "log-collector /logs endpoint is accessible with harvester admin credentials" {
  local NOW_MS START_MS END_MS
  NOW_MS=$(date +%s%3N)
  START_MS=$(( NOW_MS - 3600000 ))
  END_MS=$(( NOW_MS + 3600000 ))

  run docker compose exec -T "$HARVESTER_SERVICE" \
    sh -c "curl -sf -H 'X-Admin-Secret: ${ADMIN_SECRET}' 'http://log-collector:8787/logs?startTime=${START_MS}&endTime=${END_MS}&limit=1'"
  assert_success
  assert_output --partial '"success":true'
}
