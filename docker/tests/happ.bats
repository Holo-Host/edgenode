#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Happ installation" {
  docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'mkdir -p /home/nonroot/.hc'
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
  echo "Output of install_happ:"
  echo "$output"
  assert_success

  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "relay"
}

@test "Happ installation with invalid URL" {
  docker compose cp kando-badurl.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ kando-badurl.json test-node'
  assert_failure
  assert_output --partial "[!] Failed to download happ"
}

@test "Happ installation with valid SHA256" {
  docker compose cp kando-realsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ kando-realsha.json test-node'
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc s call -r 4444 list-apps'
  assert_output --partial "kando"
}

@test "Happ installation with invalid SHA256" {
  docker compose cp kando-badsha.json "$SERVICE_NAME":/home/nonroot/
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ kando-badsha.json test-node'
  assert_failure
  assert_output --partial "Checksum mismatch!"
}
