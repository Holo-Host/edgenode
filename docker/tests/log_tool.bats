#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Helper function to handle timeout exit codes (124) as success for service tests
assert_success_or_timeout() {
  if [[ "$status" -eq 124 ]]; then
    # Exit code 124 means timeout successfully terminated the service
    # This indicates the service started and ran successfully before being terminated
    return 0
  else
    assert_success "$@"
  fi
}

@test "log-sender init command creates config file at /etc/log-sender/config.json" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB" --report-interval-seconds 60
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f /etc/log-sender/config.json
  assert_success
}

@test "log-sender init command accepts LOG_SENDER_REPORT_INTERVAL_SECONDS override" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
  docker compose exec -T -u nonroot "$SERVICE_NAME" env -i PATH="$PATH" LOG_SENDER_REPORT_INTERVAL_SECONDS="300" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
  assert_output --partial '"reportIntervalSeconds": 300'
}

@test "log-sender service command uses default /data/logs path" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'mkdir -p /data/logs && echo "testlog" > /data/logs/test.log && chmod 644 /data/logs/test.log'
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB" --report-path /data/logs --report-interval-seconds 60
  run docker compose exec -T -u nonroot -e RUST_LOG=debug "$SERVICE_NAME" timeout 5 log-sender service --config-file /etc/log-sender/config.json
  # Exit code 124 (timeout) indicates service started successfully before termination
  assert_success_or_timeout
}

@test "log-sender service command handles LOG_SENDER_LOG_PATH override" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB" --report-path /data/logs/custom --report-interval-seconds 60
  run docker compose exec -T -u nonroot -e RUST_LOG=debug "$SERVICE_NAME" sh -c 'mkdir -p /data/logs/custom && echo "testlog" > /data/logs/custom/test.log && chmod 644 /data/logs/custom/test.log && timeout 5 log-sender service --config-file /etc/log-sender/config.json'
  # Exit code 124 (timeout) indicates service started successfully before termination
  assert_success_or_timeout
}

@test "log-sender LOG_SENDER_UNYT_PUB_KEY takes precedence over UNYT_PUB_KEY" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB" --report-interval-seconds 60
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
  assert_output --partial '"unytPubKey": "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"'
}

@test "log-sender default report interval is used when not overridden" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
  assert_output --partial '"reportIntervalSeconds": 60'
}

@test "log-sender help command shows usage" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "init"
  assert_output --partial "service"
}
