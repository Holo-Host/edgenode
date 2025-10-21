#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

is_hc_0_6_0() {
  [[ "$IMAGE_NAME" =~ hc-0\.6\.0 ]]
}

@test "Webhapp installation with valid SHA256" {
  if is_hc_0_6_0; then
    skip "Not running webhapp tests on hc-0.6.0 images due to incompatibility"
  fi
  docker cp rhymez-webhapp.json edgenode-test:/home/nonroot/
  run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ rhymez-webhapp.json test-node'
  assert_success
  run docker exec -u nonroot edgenode-test sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "rhymez"
}

@test "Webhapp installation with invalid SHA256" {
  if is_hc_0_6_0; then
    skip "Not running webhapp tests on hc-0.6.0 images due to incompatibility"
  fi
  docker cp rhymez-webhapp-badsha.json edgenode-test:/home/nonroot/
  run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ rhymez-webhapp-badsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}

@test "Webhapp installation with webhapp SHA256" {
  if is_hc_0_6_0; then
    skip "Not running webhapp tests on hc-0.6.0 images due to incompatibility"
  fi
  docker cp rhymez-webhapp-webhappsha.json edgenode-test:/home/nonroot/
  run docker exec -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ rhymez-webhapp-webhappsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}