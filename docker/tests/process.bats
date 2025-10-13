#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Holochain process runs as nonroot" {
  run docker exec edgenode-test ps aux
  assert_output --partial "nonroot.*holochain"
}