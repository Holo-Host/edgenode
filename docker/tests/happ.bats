#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Happ installation" {
  if [[ "$IMAGE_NAME" == *hc-0.6.0* ]]; then
    docker cp "$SCRIPT_DIR/relay.json" edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success
    
    run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
    assert_output --partial "relay"
  else
    docker cp kando-nosha.json edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando-nosha.json test-node'
    assert_success
    
    run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
    assert_output --partial "kando"
  fi
}
@test "Happ installation with invalid URL" {
  if [[ "$IMAGE_NAME" == *hc-0.6.0* ]]; then
    skip "Not running kando-badurl test on hc-0.6.0 images"
  else
    docker cp kando-badurl.json edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando-badurl.json test-node'
    assert_failure
    assert_output --partial "[!] Failed to download happ"
  fi
}

@test "Happ installation with valid SHA256" {
  if [[ "$IMAGE_NAME" == *hc-0.6.0* ]]; then
    skip "Not running kando-realsha test on hc-0.6.0 images"
  else
    docker cp kando-realsha.json edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando-realsha.json test-node'
    assert_success
    run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
    assert_output --partial "kando"
  fi
}

@test "Happ installation with invalid SHA256" {
  if [[ "$IMAGE_NAME" == *hc-0.6.0* ]]; then
    skip "Not running kando-badsha test on hc-0.6.0 images"
  else
    docker cp kando-badsha.json edgenode-test:/home/nonroot/
    run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando-badsha.json test-node'
    assert_failure
    assert_output --partial "Checksum mismatch!"
  fi
}