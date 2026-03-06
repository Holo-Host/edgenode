#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Conductor starts successfully" {
  # Use SERVICE_NAME directly, with fallback for backwards compatibility
  ACTUAL_SERVICE="${SERVICE_NAME:-edgenode-test}"
  
  # Get the compose files from the environment or use default
  COMPOSE_FILES="${COMPOSE_FILES:--f docker-compose.yml}"
  
  run docker compose $COMPOSE_FILES logs "$ACTUAL_SERVICE"
  assert_output --partial "Conductor ready."
}
