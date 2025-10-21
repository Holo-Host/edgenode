#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

is_unyt() {
  [[ "$IMAGE_NAME" =~ unyt ]]
}

@test "Init command fails when no public key provided" {
  run docker exec edgenode-test rm -f /etc/log-sender/config.json
  run docker exec edgenode-test log-sender init --config-file /etc/log-sender/config.json --endpoint https://httpbin.org/get --report-interval-seconds 60
  assert_failure
  assert_output --partial "the following required arguments were not provided: --unyt-pub-key"
}

@test "Init command creates config file at /etc/log-sender/config.json" {
  export UNYT_PUB_KEY="testkey123"
  run docker exec edgenode-test log-sender init --config-file /etc/log-sender/config.json --endpoint https://httpbin.org/post --unyt-pub-key "$UNYT_PUB_KEY" --report-interval-seconds 60
  assert_success
  run docker exec edgenode-test cat /etc/log-sender/config.json
  assert_output --partial '"unyt_pub_key":"testkey123"'
  unset UNYT_PUB_KEY
}

@test "Init command accepts LOG_SENDER_REPORT_INTERVAL_SECONDS override" {
  run docker exec edgenode-test rm -f /etc/log-sender/config.json
  export LOG_SENDER_REPORT_INTERVAL_SECONDS="300"
  run docker exec edgenode-test log-sender init --config-file /etc/log-sender/config.json --endpoint https://httpbin.org/get --unyt-pub-key testkey123 --report-interval-seconds "$LOG_SENDER_REPORT_INTERVAL_SECONDS"
  assert_success
  run docker exec edgenode-test cat /etc/log-sender/config.json
  assert_output --partial '"report_interval_seconds":300'
  unset LOG_SENDER_REPORT_INTERVAL_SECONDS
}

@test "Service command fails when config file is missing" {
  run docker exec edgenode-test rm /etc/log-sender/config.json
  run docker exec edgenode-test log-sender service --config-file /etc/log-sender/config.json
  assert_failure
  assert_output --partial "Config file not found"
}

@test "Service command processes logs from /var/log" {
  if is_unyt; then
    run docker exec edgenode-test sh -c 'echo "testlog" > /var/log/test.log'
    run docker exec edgenode-test log-sender service --config-file /etc/log-sender/config.json --report-path /var/log
    assert_output --partial "Processing logs from /var/log/test.log"
  else
    skip "Not running on unyt image"
  fi
}

@test "Service command handles environment variable overrides" {
  export LOG_SENDER_LOG_PATH="/custom/log/path"
  run docker exec edgenode-test log-sender service --config-file /etc/log-sender/config.json --report-path "$LOG_SENDER_LOG_PATH"
  assert_output --partial "Processing logs from /custom/log/path"
  unset LOG_SENDER_LOG_PATH
}

@test "LOG_SENDER_UNYT_PUB_KEY takes precedence over UNYT_PUB_KEY" {
  run docker exec edgenode-test rm -f /etc/log-sender/config.json
  export UNYT_PUB_KEY="fallback"
  export LOG_SENDER_UNYT_PUB_KEY="override"
  run docker exec edgenode-test log-sender init --config-file /etc/log-sender/config.json --endpoint https://httpbin.org/get --unyt-pub-key "$UNYT_PUB_KEY" --report-interval-seconds 60
  assert_success
  run docker exec edgenode-test cat /etc/log-sender/config.json
  assert_output --partial '"unyt_pub_key":"override"'
  unset UNYT_PUB_KEY LOG_SENDER_UNYT_PUB_KEY
}

@test "Default paths are used when not overridden" {
  run docker exec edgenode-test rm -f /etc/log-sender/config.json
  run docker exec edgenode-test log-sender init --config-file /etc/log-sender/config.json --endpoint https://httpbin.org/get --unyt-pub-key testkey123 --report-interval-seconds 60
  assert_success
  run docker exec edgenode-test cat /etc/log-sender/config.json
  assert_output --partial '"log_path":"/var/log"'
  assert_output --partial '"config_path":"/etc/log-sender"'
}