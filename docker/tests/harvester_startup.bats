#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

HARVESTER_SERVICE="${SERVICE_NAME:-edgenode-harvester}"

setup() {
  if ! docker compose ps "$HARVESTER_SERVICE" 2>/dev/null | grep -q "running\|Up"; then
    skip "edgenode-harvester service is not running"
  fi
}

@test "Conductor starts successfully" {
  run docker compose logs "$HARVESTER_SERVICE"
  assert_output --partial "Conductor ready."
}

@test "unyt.happ is installed" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    hc client call -p 4444 list-apps
  assert_success
  assert_output --partial "unyt"
}

@test "log-harvester has connected to app websocket" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    test -s /data/logs/log-harvester.log
  assert_success
}

@test "Harvester config is initialized" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    test -f /data/log-harvester/config.json
  assert_success
}

@test "Harvester config contains collectorUrl" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    jq -e '.collectorUrl' /data/log-harvester/config.json
  assert_success
}

@test "log-harvester service starts" {
  run docker compose exec -T "$HARVESTER_SERVICE" \
    sh -c "cat /data/logs/startup.log"
  assert_success
  assert_output --partial "Starting log-harvester service..."
}
