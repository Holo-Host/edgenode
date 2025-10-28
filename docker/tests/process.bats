#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Holochain process runs as nonroot" {
  run docker-compose exec -T edgenode-test sh -c "ps aux | grep -E 'nonroot.*holochain'"
  assert_success
}
