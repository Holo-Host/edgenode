#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Webhapp installation with valid SHA256" {
  docker compose cp ziptest-realsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-realsha.json test-node'
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "ziptest"
}

@test "Webhapp installation with invalid SHA256" {
  docker compose cp ziptest-badsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-badsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}

@test "Webhapp installation with webhapp SHA256" {
  docker compose cp ziptest-webhappsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-webhappsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}
