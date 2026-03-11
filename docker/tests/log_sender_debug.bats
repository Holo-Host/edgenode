#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "log-sender debug" {
  run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'mkdir -p /data/logs/debug && echo "{\"k\":\"metric\",\"t\":\"123\",\"value\":123}" > /data/logs/debug/test.jsonl'
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init --config-file /etc/log-sender/debug.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB" --report-path /data/logs/debug --report-interval-seconds 1
  assert_success
  run docker compose exec -T -u nonroot "$SERVICE_NAME" cat /etc/log-sender/debug.json
  assert_success
  run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" timeout 5 log-sender service --config-file /etc/log-sender/debug.json
  assert_success
}
