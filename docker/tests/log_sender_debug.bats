#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

is_unyt() {
  [[ "$IMAGE_NAME" =~ unyt ]]
}

@test "log-sender debug" {
  if is_unyt; then
    run docker compose -p log-sender-debug -f docker-compose.base.yml -f docker-compose.unyt.yml exec -T -u nonroot edgenode-unyt sh -c 'mkdir -p /data/logs/debug && echo "{\"k\":\"metric\",\"t\":\"123\",\"value\":123}" > /data/logs/debug/test.jsonl'
    assert_success
    run docker compose -p log-sender-debug -f docker-compose.base.yml -f docker-compose.unyt.yml exec -T -u nonroot edgenode-unyt log-sender init --config-file /etc/log-sender/debug.json --endpoint http://log-collector:8787 --unyt-pub-key "uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB" --report-path /data/logs/debug --report-interval-seconds 1
    assert_success
    run docker compose -p log-sender-debug -f docker-compose.base.yml -f docker-compose.unyt.yml exec -T -u nonroot edgenode-unyt cat /etc/log-sender/debug.json
    assert_success
    run docker compose -p log-sender-debug -f docker-compose.base.yml -f docker-compose.unyt.yml exec -T -u nonroot -e RUST_LOG=info edgenode-unyt timeout 5 log-sender service --config-file /etc/log-sender/debug.json
    assert_success
  else
    skip "Not running on unyt image"
  fi
}