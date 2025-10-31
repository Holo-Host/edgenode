#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Holochain process runs as nonroot" {
  # Use SERVICE_NAME directly, with fallback for backwards compatibility
  ACTUAL_SERVICE="${SERVICE_NAME:-edgenode-test}"
  
  run docker compose exec -T "$ACTUAL_SERVICE" sh -c "ps aux | grep -E 'nonroot.*holochain'"
  assert_success
}
