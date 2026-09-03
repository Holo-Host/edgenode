#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Happ installation" {
  docker compose cp "$SCRIPT_DIR/ziptest.json" "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'mkdir -p /home/nonroot/.hc'
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest.json test-node'
  echo "Output of install_happ:"
  echo "$output"
  assert_success

  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "ziptest"
}

@test "Happ installation with invalid URL" {
  docker compose cp ziptest-badurl.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-badurl.json test-node'
  assert_failure
  assert_output --partial "[!] Failed to download happ"
}

@test "Happ installation with valid SHA256" {
  docker compose cp ziptest-realsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-realsha.json test-node'
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "ziptest"
}

@test "Happ installation with invalid SHA256" {
  docker compose cp ziptest-badsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-badsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}
