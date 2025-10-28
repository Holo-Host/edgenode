#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Data persists across container restarts" {
  TEST_STRING="persistence is working"
  TEST_FILE="/data/test-file.txt"

  run docker-compose exec -T edgenode-test sh -c "echo '$TEST_STRING' > $TEST_FILE"
  assert_success

  docker-compose restart edgenode-test
  sleep 5

  run docker-compose exec -T edgenode-test cat "$TEST_FILE"
  assert_output "$TEST_STRING"
}
