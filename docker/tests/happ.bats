#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Happ installation" {
  docker cp kando.json edgenode-test:/home/nonroot/
  run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando.json test-node'
  assert_success
  
  run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "kando"
}