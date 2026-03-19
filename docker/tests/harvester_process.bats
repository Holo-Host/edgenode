#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

HARVESTER_SERVICE="${SERVICE_NAME:-edgenode-harvester}"

setup() {
  if ! docker compose ps "$HARVESTER_SERVICE" 2>/dev/null | grep -q "running\|Up"; then
    skip "edgenode-harvester service is not running"
  fi
}

@test "Holochain process runs as nonroot" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    sh -c "ps aux | grep -E 'nonroot.*holochain'"
  assert_success
}

@test "log-harvester node process runs as nonroot" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    sh -c "ps aux | grep -E 'nonroot.*node'"
  assert_success
}
