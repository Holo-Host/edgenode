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

is_unyt() {
  [[ "$IMAGE_NAME" =~ unyt ]]
}

@test "log-sender init command creates config file at /etc/log-sender/config.json" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO" --report-interval-seconds 60
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f /etc/log-sender/config.json
    assert_success
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool init command creates config file at /etc/log-sender/config.json" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
    docker compose cp setup_test_env.sh "$SERVICE_NAME":/tmp/setup_test_env.sh
    run docker compose exec -T "$SERVICE_NAME" chmod +x /tmp/setup_test_env.sh
    run docker compose exec -T -u nonroot "$SERVICE_NAME" /tmp/setup_test_env.sh log_tool init --endpoint http://log-collector:8787 --report-interval-seconds 60
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f /etc/log-sender/config.json
    assert_success
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender init command accepts LOG_SENDER_REPORT_INTERVAL_SECONDS override" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
    docker compose exec -T -u nonroot "$SERVICE_NAME" env -i PATH="$PATH" LOG_SENDER_REPORT_INTERVAL_SECONDS="300" log-sender init --config-file /etc/log-sender/config.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO"
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
    assert_output --partial '"reportIntervalSeconds": 300'
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool init command accepts LOG_SENDER_REPORT_INTERVAL_SECONDS override" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
    docker compose cp setup_test_env.sh "$SERVICE_NAME":/tmp/setup_test_env.sh
    run docker compose exec -T "$SERVICE_NAME" chmod +x /tmp/setup_test_env.sh
    docker compose exec -T -u nonroot "$SERVICE_NAME" env -i PATH="$PATH" LOG_SENDER_REPORT_INTERVAL_SECONDS="300" /tmp/setup_test_env.sh log_tool init --endpoint http://log-collector:8787
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
    assert_output --partial '"reportIntervalSeconds": 300'
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool service command uses default /data/logs path" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'mkdir -p /data/logs && echo "testlog" > /data/logs/test.log && chmod 644 /data/logs/test.log'
    docker compose cp setup_test_env.sh "$SERVICE_NAME":/tmp/setup_test_env.sh
    run docker compose exec -T "$SERVICE_NAME" chmod +x /tmp/setup_test_env.sh
    run docker compose exec -T -u nonroot -e RUST_LOG=debug "$SERVICE_NAME" timeout 5 /tmp/setup_test_env.sh log_tool service
    # Exit code 124 (timeout) indicates service started successfully before termination
    assert_success_or_timeout
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool service command handles LOG_SENDER_LOG_PATH override" {
  if is_unyt; then
    docker compose cp setup_test_env.sh "$SERVICE_NAME":/tmp/setup_test_env.sh
    run docker compose exec -T "$SERVICE_NAME" chmod +x /tmp/setup_test_env.sh
    run docker compose exec -T -u nonroot -e RUST_LOG=debug "$SERVICE_NAME" sh -c 'export LOG_SENDER_LOG_PATH="/data/logs/custom" && mkdir -p /data/logs/custom && echo "testlog" > /data/logs/custom/test.log && chmod 644 /data/logs/custom/test.log && timeout 5 /tmp/setup_test_env.sh log_tool service'
    # Exit code 124 (timeout) indicates service started successfully before termination
    assert_success_or_timeout
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool LOG_SENDER_UNYT_PUB_KEY takes precedence over UNYT_PUB_KEY" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
    docker compose cp setup_test_env.sh "$SERVICE_NAME":/tmp/setup_test_env.sh
    run docker compose exec -T "$SERVICE_NAME" chmod +x /tmp/setup_test_env.sh
    docker compose exec -T -u nonroot "$SERVICE_NAME" env -i PATH="$PATH" UNYT_PUB_KEY="uhCAklQrs-YcZLp1h_EmLp9bCMgI2KeHaSzcyW-6AeLLGdB39aCX8" LOG_SENDER_UNYT_PUB_KEY="uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO" /tmp/setup_test_env.sh log_tool init --endpoint http://log-collector:8787 --report-interval-seconds 60
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
    assert_output --partial '"unytPubKey": "uhCAkDM-p0oBsRJn5Ebpk8c_TNkrp2NEwF9C5ppJq8cE77I-n3qfO"'
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool default report interval is used when not overridden" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json
    docker compose cp setup_test_env.sh "$SERVICE_NAME":/tmp/setup_test_env.sh
    run docker compose exec -T "$SERVICE_NAME" chmod +x /tmp/setup_test_env.sh
    run docker compose exec -T -u nonroot "$SERVICE_NAME" /tmp/setup_test_env.sh log_tool init --endpoint http://log-collector:8787 
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/config.json
    assert_output --partial '"reportIntervalSeconds": 60'
  else
    skip "Not running on unyt image"
  fi
}

@test "log_tool help command shows usage" {
  if is_unyt; then
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log_tool help
    assert_failure
    assert_output --partial "Usage:"
    assert_output --partial "init"
    assert_output --partial "service"
  else
    skip "Not running on unyt image"
  fi
}