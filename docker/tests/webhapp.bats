#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Webhapp installation with valid SHA256" {
  skip "Needs a HC 0.6.1-rc.3-compatible webhapp - rhymez 0.1.5 uses bundle manifest v1, HC 0.6.1-rc.3 expects v0"
  docker compose cp rhymez-webhapp.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ rhymez-webhapp.json test-node'
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "rhymez"
}

@test "Webhapp installation with invalid SHA256" {
  skip "Needs a HC 0.6.1-rc.3-compatible webhapp - rhymez 0.1.5 uses bundle manifest v1, HC 0.6.1-rc.3 expects v0"
  docker compose cp rhymez-webhapp-badsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ rhymez-webhapp-badsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}

@test "Webhapp installation with webhapp SHA256" {
  skip "Needs a HC 0.6.1-rc.3-compatible webhapp - rhymez 0.1.5 uses bundle manifest v1, HC 0.6.1-rc.3 expects v0"
  docker compose cp rhymez-webhapp-webhappsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ rhymez-webhapp-webhappsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}
