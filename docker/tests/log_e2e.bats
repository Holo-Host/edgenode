#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

is_unyt() {
  [[ "$IMAGE_NAME" =~ unyt ]]
}

@test "log_tool sends data and increases the metric count in the database" {
  if is_unyt; then
    # Ensure jq is installed
    if ! command -v jq &> /dev/null; then
      echo "jq could not be found, skipping test"
      skip "jq is not installed"
    fi

    # Init log_tool with a short report interval
    run docker-compose exec -T edgenode-test rm -f /etc/log-sender/config.json
    docker-compose cp setup_test_env.sh edgenode-test:/tmp/setup_test_env.sh
    run docker-compose exec -T edgenode-test chmod +x /tmp/setup_test_env.sh
    run docker-compose exec -T -u nonroot edgenode-test /tmp/setup_test_env.sh log_tool init --endpoint http://log-collector:8787 --report-interval-seconds 5
    assert_success

    # Get initial metric count
    run docker-compose exec -T log-collector wrangler d1 execute log-collector-db --command "SELECT COUNT(*) FROM metrics" --json
    assert_success
    initial_count=$(echo "$output" | jq '.[0].results[0]["COUNT(*)"]')

    # Create a dummy log file with unique content
    DUMMY_LOG_CONTENT="{\"k\":\"test\",\"t\":\"$(date +%s)000000\"}"
    run docker-compose exec -T edgenode-test sh -c "echo '$DUMMY_LOG_CONTENT' > /data/logs/bats_e2e_test.jsonl && chmod 644 /data/logs/bats_e2e_test.jsonl"
    assert_success

    # Run log_tool service to send the log. Run for 20 seconds.
    run docker-compose exec -T -u nonroot -e RUST_LOG=debug edgenode-test timeout 20 /tmp/setup_test_env.sh log_tool service
    echo "log_tool service output: $output"

    # Wait for processing
    sleep 5

    # Get final metric count
    run docker-compose exec -T log-collector wrangler d1 execute log-collector-db --command "SELECT COUNT(*) FROM metrics" --json
    assert_success
    final_count=$(echo "$output" | jq '.[0].results[0]["COUNT(*)"]')

    # Assert that the count has increased
    assert [ "$final_count" -gt "$initial_count" ]
  else
    skip "Not running on unyt image"
  fi
}