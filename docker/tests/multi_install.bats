#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

is_hc_0_6_0() {
  [[ "$IMAGE_NAME" =~ hc0\.6\.0 ]] || [[ "$IMAGE_NAME" =~ unyt ]]
}

@test "Multiple happ installation" {
  # This test only runs on versions that support the kando happ.
  if ! is_hc_0_6_0; then
    # Install a first happ
    docker-compose cp "$SCRIPT_DIR/kando-nosha.json" edgenode-test:/home/nonroot/
    run docker-compose exec -T -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando-nosha.json test-node-1'
    assert_success

    # Install a second happ to test DNA_HASH extraction with multiple apps present
    run docker-compose exec -T -u nonroot edgenode-test sh -c 'cd /home/nonroot && install_happ kando-nosha.json test-node-2'
    assert_success
  else
    skip "Test not applicable for hc-0.6.0 images as a suitable happ with initZomeCalls is not available."
  fi
}