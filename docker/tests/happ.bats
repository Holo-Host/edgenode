#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Happ installation" {
  if [ "$IMAGE_NAME" = "local-edgenode-go-pion" ]; then
    docker cp relay.json edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success
    
    run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
    assert_output --partial "relay"
  else
    docker cp kando.json edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando.json test-node'
    assert_success
    
    run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
    assert_output --partial "kando"
  fi
}