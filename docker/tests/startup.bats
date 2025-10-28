#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Conductor starts successfully" {
  run docker-compose logs edgenode-test
  assert_output --partial "Conductor ready."
}
