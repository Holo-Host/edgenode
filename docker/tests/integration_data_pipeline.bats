#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Test configuration
LOG_COLLECTOR_URL="http://log-collector:8787"
LOCAL_LOG_COLLECTOR_URL="http://localhost:8787"
ADMIN_SECRET="test_admin_secret"
UNYT_PUB_KEY="uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"



# Helper function to clear database before tests
clear_test_data() {
    echo "=== CLEARING TEST DATABASE ==="
    
    # Clear all test data from previous runs
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="DELETE FROM metrics WHERE source LIKE 'integration_test_%' OR source LIKE 'e2e_integration_%';" 2>/dev/null || true
    
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="DELETE FROM drone_registrations WHERE unyt_pub_key = '$UNYT_PUB_KEY';" 2>/dev/null || true
    
    echo "✅ Database cleared for integration tests"
}

# Helper function to verify database state
verify_database_state() {
    local test_name="$1"
    local expected_metrics="${2:-0}"
    local expected_registrations="${3:-0}"
    
    echo "=== DATABASE STATE FOR $test_name ==="
    
    local metrics_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    local registrations_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "Current database state:"
    echo "  Metrics: $metrics_count"
    echo "  Drone Registrations: $registrations_count"
    
    if [[ "$metrics_count" -ge "$expected_metrics" && "$registrations_count" -ge "$expected_registrations" ]]; then
        echo "✅ Database state verification passed"
        return 0
    else
        echo "❌ Database state verification failed"
        echo "  Expected: >= $expected_metrics metrics, >= $expected_registrations registrations"
        echo "  Actual: $metrics_count metrics, $registrations_count registrations"
        return 1
    fi
}

# Helper function to extract drone_id from config
get_drone_id() {
    local config_file="$1"
    docker compose exec -T -u nonroot "$SERVICE_NAME" jq '.droneId' "$config_file" 2>/dev/null || echo ""
}

# Helper function to wait for data to appear in database
wait_for_database_data() {
    local max_wait="${1:-30}"
    local check_interval="${2:-2}"
    local expected_count="${3:-1}"
    
    echo "Waiting up to ${max_wait}s for data to appear in database (expecting >= $expected_count records)..."
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local metrics_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
            --command="SELECT COUNT(*) as total FROM metrics WHERE source LIKE 'integration_test_%';" 2>/dev/null | jq -r '..total // 0' 2>/dev/null || echo "0")
        
        if [[ "$metrics_count" -ge "$expected_count" ]]; then
            echo "✅ Data found in database: $metrics_count integration test metrics"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        
        # Show progress every 10 seconds
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            echo "  Still waiting... ($elapsed/${max_wait}s, found: $metrics_count metrics)"
        fi
    done
    
    echo "⚠️  Expected data not found after ${max_wait}s (found: $metrics_count metrics)"
    return 1
}

@setup() {
    # Verify prerequisites
    if ! curl -s "http://localhost:8787/" 2>/dev/null | grep -q "log-collector\|ok"; then
        skip "Log-collector service not responding"
    fi
    
    # Clear database before each test
    clear_test_data
}

@teardown() {
    # Show final database state
    echo "=== FINAL DATABASE STATE AFTER TEST ==="
    verify_database_state "POST-TEST"
    
    # Cleanup test artifacts
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf /data/logs/integration_test_* 2>/dev/null || true
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/integration_*.json 2>/dev/null || true
    rm -f /tmp/integration_test_*.jsonl 2>/dev/null || true
}

@test "integration: log-sender populates database with single metric" {
    echo "=== INTEGRATION TEST: Single Metric Database Population ==="
    
    local test_config="/etc/log-sender/integration_single.json"
    local test_log_dir="/data/logs/integration_test_single"
    local test_namespace="integration_single_$(date +%s)"
    
    # Setup test environment
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    # Create single metric log entry
    local current_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$current_time\",\"value\":42.5,\"source\":\"integration_test_single\",\"unit\":1,\"tags\":\"{\\\"namespace\\\":\\\"$test_namespace\\\",\\\"test\\\":\\\"single_metric\\\"}\"}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $test_log_dir/metrics.jsonl"
    assert_success
    
    # Initialize log-sender
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir/" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    # Start log-sender service
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 20 log-sender service \
        --config-file "$test_config"
    echo "Output of log-sender service:"
    echo "$output"
    
    # Wait for data to appear in database
    wait_for_database_data 25 1 1
    
    # Verify data in database
    echo "=== VERIFYING DATABASE CONTENTS ==="
    local db_metrics=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT id, signing_pub_key, metric_value, metric_timestamp, source FROM metrics WHERE source = 'integration_test_single' ORDER BY id DESC LIMIT 5;" 2>/dev/null)
    
    echo "Database query result:"
    echo "$db_metrics"
    
    # Verify the specific metric was stored
    if echo "$db_metrics" | grep -q "integration_test_single"; then
        echo "✅ SUCCESS: Single metric successfully stored in database"
        
    else
        echo "❌ FAILURE: Single metric not found in database"
        return 1
    fi
}

@test "integration: log-sender populates database with multiple metrics" {
    echo "=== INTEGRATION TEST: Multiple Metrics Database Population ==="
    
    local test_config="/etc/log-sender/integration_multi.json"
    local test_log_dir="/data/logs/integration_test_multi"
    local test_namespace="integration_multi_$(date +%s)"
    
    # Setup test environment
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    # Create multiple metric log entries
    local current_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$current_time\",\"value\":100.0,\"source\":\"integration_test_multi\",\"unit\":1,\"tags\":\"{\\\"namespace\\\":\\\"$test_namespace\\\",\\\"test\\\":\\\"multi_metric\\\",\\\"index\\\":1}\"}
    {\"k\":\"metric\",\"t\":\"$((current_time + 1000000))\",\"value\":200.5,\"source\":\"integration_test_multi\",\"unit\":2,\"tags\":\"{\\\"namespace\\\":\\\"$test_namespace\\\",\\\"test\\\":\\\"multi_metric\\\",\\\"index\\\":2}\"}
    {\"k\":\"metric\",\"t\":\"$((current_time + 2000000))\",\"value\":150.25,\"source\":\"integration_test_multi\",\"unit\":1,\"tags\":\"{\\\"namespace\\\":\\\"$test_namespace\\\",\\\"test\\\":\\\"multi_metric\\\",\\\"index\\\":3}\"}
    {\"k\":\"metric\",\"t\":\"$((current_time + 3000000))\",\"value\":75.75,\"source\":\"integration_test_multi\",\"unit\":3,\"tags\":\"{\\\"namespace\\\":\\\"$test_namespace\\\",\\\"test\\\":\\\"multi_metric\\\",\\\"index\\\":4}\"}
    {\"k\":\"start\",\"t\":\"$((current_time + 4000000))\",\"component\":\"integration_test\",\"status\":\"started\"}
    {\"k\":\"fetchedOps\",\"t\":\"$((current_time + 5000000))\",\"count\":42,\"latency\":150}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $test_log_dir/metrics.jsonl"
    assert_success
    
    # Initialize log-sender
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    # Start log-sender service
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 25 log-sender service \
        --config-file "$test_config"
    
    # Wait for data to appear in database
    wait_for_database_data 30 2 4
    
    # Verify multiple metrics in database
    echo "=== VERIFYING MULTIPLE METRICS IN DATABASE ==="
    local db_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_multi';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "Found $db_count metrics in database (expected: >= 4)"
    
    if [[ "$db_count" -ge 4 ]]; then
        echo "✅ SUCCESS: Multiple metrics ($db_count) successfully stored in database"
        
        # Show sample of stored metrics
        local sample_metrics=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
            --command="SELECT metric_value, source, metric_timestamp FROM metrics WHERE source = 'integration_test_multi' ORDER BY metric_timestamp LIMIT 3;" 2>/dev/null)
        echo "Sample stored metrics:"
        echo "$sample_metrics"
    else
        echo "❌ FAILURE: Expected >= 4 metrics, found only $db_count"
        return 1
    fi
}

@test "integration: database persistence across multiple log-sender runs" {
    echo "=== INTEGRATION TEST: Database Persistence Across Runs ==="
    
    local test_config="/etc/log-sender/integration_persistence.json"
    local test_log_dir="/data/logs/integration_test_persistence"
    
    # First run - create initial data
    echo "--- FIRST RUN: Creating initial data ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    local first_run_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$first_run_time\",\"value\":100.0,\"source\":\"integration_test_persistence\",\"unit\":1}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $test_log_dir/first_run.jsonl"
    assert_success
    
    # Initialize and run first time
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    # Run log-sender again with same config (should use existing registration)
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service \
        --config-file "$test_config"
    
    # Wait for first run data
    wait_for_database_data 20 1 1
    
    # Check database state after first run
    local after_first=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_persistence';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "After first run: $after_first metrics in database"
    
    # Second run - add more data
    echo "--- SECOND RUN: Adding more data ---"
    local second_run_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$second_run_time\",\"value\":200.0,\"source\":\"integration_test_persistence\",\"unit\":2}
    {\"k\":\"metric\",\"t\":\"$((second_run_time + 1000000))\",\"value\":300.0,\"source\":\"integration_test_persistence\",\"unit\":1}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $test_log_dir/second_run.jsonl"
    
    # Run log-sender again with same config (should use existing registration)
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service \
        --config-file "$test_config"
    
    # Wait for second run data
    wait_for_database_data 20 2 2
    
    # Verify persistence
    local after_second=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_persistence';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "After second run: $after_second metrics in database"
    
    if [[ "$after_second" -gt "$after_first" ]]; then
        echo "✅ SUCCESS: Database persistence confirmed ($after_first → $after_second metrics)"
        echo "✅ Second run successfully added new data without losing existing data"
    else
        echo "❌ FAILURE: Database persistence failed (expected > $after_first, got $after_second)"
        return 1
    fi
}

@test "integration: real-time metric processing and storage" {
    echo "=== INTEGRATION TEST: Real-time Processing ==="
    
    local test_config="/etc/log-sender/integration_realtime.json"
    local test_log_dir="/data/logs/integration_test_realtime"
    
    # Setup test environment
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    run docker compose exec -T -u nonroot "$SERVICE_NAME" touch "$test_log_dir/realtime_1.jsonl"
    assert_success
    
    # Initialize log-sender first
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 3  # 3 second intervals for real-time testing
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    # Start log-sender service in background
    echo "--- Starting log-sender service for real-time processing ---"
    docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 30 log-sender service \
        --config-file "$test_config" > /tmp/realtime_service.log 2>&1 &
    
    local service_pid=$!
    echo "Service started with PID: $service_pid"
    
    # Wait for service to initialize
    sleep 5
    
    # Create metrics in real-time while service is running
    echo "--- Creating metrics in real-time ---"
    local base_time=$(($(date +%s) * 1000000))
    
    for i in {1..5}; do
        local entry_time=$((base_time + (i * 500000)))  # 0.5 second intervals
        local metric_value=$((i * 25))
        
        echo "Creating metric $i: value=$metric_value at $(date)"
        
        local log_content="{\"k\":\"metric\",\"t\":\"$entry_time\",\"value\":$metric_value,\"source\":\"integration_test_realtime\",\"unit\":1,\"tags\":\"{\\\"realtime_index\\\":$i}\"}"
        run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $test_log_dir/realtime_$i.jsonl"
        assert_success
        
        # Wait a bit between metrics
        sleep 2
    done
    
    # Wait for processing
    echo "--- Waiting for real-time processing to complete ---"
    wait_for_database_data 25 2 3
    
    # Stop the service
    kill $service_pid 2>/dev/null || true
    wait $service_pid 2>/dev/null || true
    
    # Verify real-time processing results
    echo "=== VERIFYING REAL-TIME PROCESSING RESULTS ==="
    local realtime_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_realtime';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "Real-time metrics processed: $realtime_count (expected: >= 3)"
    
    if [[ "$realtime_count" -ge 3 ]]; then
        echo "✅ SUCCESS: Real-time processing worked ($realtime_count metrics stored)"
        
        # Show the metrics that were processed
        local sample_realtime=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
            --command="SELECT metric_value, metric_timestamp FROM metrics WHERE source = 'integration_test_realtime' ORDER BY metric_timestamp LIMIT 3;" 2>/dev/null)
        echo "Sample real-time metrics:"
        echo "$sample_realtime"
    else
        echo "❌ FAILURE: Real-time processing failed (expected >= 3, got $realtime_count)"
        echo "Service log excerpt:"
        tail -20 /tmp/realtime_service.log
        return 1
    fi
}

@test "integration: data integrity and validation" {
    echo "=== INTEGRATION TEST: Data Integrity and Validation ==="
    
    local test_config="/etc/log-sender/integration_integrity.json"
    local test_log_dir="/data/logs/integration_test_integrity"
    
    # Setup test environment
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    # Create test data with various data types and edge cases
    local current_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$current_time\",\"value\":0.0,\"source\":\"integration_test_integrity\",\"unit\":1}
    {\"k\":\"metric\",\"t\":\"$((current_time + 1000000))\",\"value\":999999.99,\"source\":\"integration_test_integrity\",\"unit\":2}
    {\"k\":\"metric\",\"t\":\"$((current_time + 2000000))\",\"value\":-100.5,\"source\":\"integration_test_integrity\",\"unit\":1}
    {\"k\":\"event\",\"t\":\"$((current_time + 3000000))\",\"event_type\":\"test_event\",\"data\":\"{\\\"test\\\":true,\\\"number\\\":42}\"}
    {\"k\":\"start\",\"t\":\"$((current_time + 4000000))\",\"component\":\"integrity_test\",\"status\":\"initialized\",\"metadata\":\"{\\\"version\\\":\\\"1.0\\\",\\\"env\\\":\\\"test\\\"}\"}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $test_log_dir/integrity.jsonl"
    assert_success
    
    # Initialize and run log-sender
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 20 log-sender service \
        --config-file "$test_config"
    
    # Wait for processing
    wait_for_database_data 25 1 2
    
    # Verify data integrity
    echo "=== VERIFYING DATA INTEGRITY ==="
    
    # Check that specific values were preserved
    local zero_metric=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT metric_value FROM metrics WHERE source = 'integration_test_integrity' AND metric_value = 0.0 LIMIT 1;" 2>/dev/null | grep -o '"metric_value": [0-9.-]*' | grep -o '[0-9.-]*' | head -1 || echo "")
    
    local high_metric=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT metric_value FROM metrics WHERE source = 'integration_test_integrity' AND metric_value = 999999.99 LIMIT 1;" 2>/dev/null | grep -o '"metric_value": [0-9.-]*' | grep -o '[0-9.-]*' | head -1 || echo "")
    
    local negative_metric=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT metric_value FROM metrics WHERE source = 'integration_test_integrity' AND metric_value = -100.5 LIMIT 1;" 2>/dev/null | grep -o '"metric_value": [0-9.-]*' | grep -o '[0-9.-]*' | head -1 || echo "")
    
    echo "Data integrity check results:"
    echo "  Zero value (0.0): $zero_metric"
    echo "  High value (999999.99): $high_metric"  
    echo "  Negative value (-100.5): $negative_metric"
    
    if [[ -n "$zero_metric" && -n "$high_metric" && -n "$negative_metric" ]]; then
        echo "✅ SUCCESS: Data integrity preserved (all edge case values stored correctly)"
    else
        echo "❌ FAILURE: Data integrity issues detected"
        return 1
    fi
    
    # Verify timestamps are preserved
    local timestamp_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_integrity' AND metric_timestamp >= $current_time;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    if [[ "$timestamp_count" -ge 2 ]]; then
        echo "✅ SUCCESS: Timestamps preserved correctly"
    else
        echo "❌ FAILURE: Timestamp integrity issues"
        return 1
    fi
}

@test "integration: complete cleanup and reset verification" {
    echo "=== INTEGRATION TEST: Complete Cleanup and Reset ==="
    
    # First, populate database with test data
    local populate_config="/etc/log-sender/integration_cleanup.json"
    local populate_log_dir="/data/logs/integration_test_cleanup"
    
    echo "--- PHASE 1: Populate database with test data ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$populate_log_dir"
    assert_success
    local cleanup_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$cleanup_time\",\"value\":999.0,\"source\":\"integration_test_cleanup\",\"unit\":1}
    {\"k\":\"metric\",\"t\":\"$((cleanup_time + 1000000))\",\"value\":888.0,\"source\":\"integration_test_cleanup\",\"unit\":2}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $populate_log_dir/cleanup_test.jsonl"
    assert_success
    
    # Initialize and run to populate data
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$populate_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$populate_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success
    
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service \
        --config-file "$populate_config"
    
    # Wait for data to be stored
    wait_for_database_data 20 1 2
    
    # Verify data was stored
    local before_cleanup=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_cleanup';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "Data stored before cleanup: $before_cleanup metrics"
    
    if [[ "$before_cleanup" -lt 2 ]]; then
        echo "❌ FAILURE: Could not populate database for cleanup test"
        return 1
    fi
    
    # Now perform cleanup
    echo "--- PHASE 2: Perform cleanup operations ---"
    
    # Clear test data using the same method as @setup
    clear_test_data
    
    # Verify cleanup
    local after_cleanup=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_cleanup';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "Data remaining after cleanup: $after_cleanup metrics"
    
    if [[ "$after_cleanup" -eq 0 ]]; then
        echo "✅ SUCCESS: Complete cleanup verification passed (test data removed)"
    else
        echo "❌ FAILURE: Cleanup incomplete ($after_cleanup test metrics still present)"
        return 1
    fi
    
    # Verify system can still function after cleanup
    echo "--- PHASE 3: Verify system functionality after cleanup ---"
    
    # Create new test to verify system still works
    local verification_config="/etc/log-sender/integration_verification.json"
    local verification_log_dir="/data/logs/integration_test_verification"
    
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$verification_log_dir"
    assert_success
    local verify_time=$(($(date +%s) * 1000000))
    local log_content="{\"k\":\"metric\",\"t\":\"$verify_time\",\"value\":777.0,\"source\":\"integration_test_verification\",\"unit\":1}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $verification_log_dir/verification.jsonl"
    assert_success
    
    # Run verification test
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$verification_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$verification_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    # Install hApp, which will trigger DNA registration
    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success
    
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service \
        --config-file "$verification_config"
    
    # Verify system still works after cleanup
    wait_for_database_data 20 1 1
    
    local after_verification=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE source = 'integration_test_verification';" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    if [[ "$after_verification" -ge 1 ]]; then
        echo "✅ SUCCESS: System functionality verified after cleanup (new data stored successfully)"
    else
        echo "❌ FAILURE: System not functioning properly after cleanup"
        return 1
    fi
}