#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Multiple happ installation with initZomeCalls" {
  docker compose cp "$SCRIPT_DIR/ziptest-init.json" "$SERVICE_NAME":/home/nonroot/

  # First install: exercises zome-call-auth + zome-call against the fresh cell
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-init.json test-node-1'
  assert_success
  assert_output --partial "calling create_thing"

  # Second install with a different agent: DNA_HASH extraction must pick the right app
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ ziptest-init.json test-node-2'
  assert_success
  assert_output --partial "calling create_thing"

  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'hc client call -p 4444 list-apps | jq -r ".[].installed_app_id"'
  assert_success
  [ "$(echo "$output" | grep -c '^ziptest::0.6.0-dev.0::')" -ge 2 ]
}
