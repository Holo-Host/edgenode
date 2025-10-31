#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Data persists across container restarts" {
  TEST_STRING="persistence is working"
  TEST_FILE="/data/test-file.txt"

  # Use SERVICE_NAME directly, with fallback for backwards compatibility
  ACTUAL_SERVICE="${SERVICE_NAME:-edgenode-test}"

  run docker compose exec -T "$ACTUAL_SERVICE" sh -c "echo '$TEST_STRING' > $TEST_FILE"
  assert_success

  # Restart the container using docker restart command
  # Docker Compose creates containers with project prefix + service name
  # Use COMPOSE_PROJECT_NAME to construct the correct container name
  PROJECT_NAME="${COMPOSE_PROJECT_NAME:-edgenode}"
  CONTAINER_NAME="${PROJECT_NAME}-${ACTUAL_SERVICE}-1"
  docker restart "$CONTAINER_NAME"
  sleep 10

  run docker compose exec -T "$ACTUAL_SERVICE" cat "$TEST_FILE"
  assert_output "$TEST_STRING"
}
