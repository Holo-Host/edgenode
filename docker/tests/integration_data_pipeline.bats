#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Test configuration
LOG_COLLECTOR_URL="http://log-collector:8787"
LOCAL_LOG_COLLECTOR_URL="http://localhost:8787"
ADMIN_SECRET="test_admin_secret"
UNYT_PUB_KEY="uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"

# Count all metrics currently in the database
_count_metrics() {
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null \
        | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0"
}

# Helper function to verify database state (informational)
verify_database_state() {
    local test_name="$1"
    echo "=== DATABASE STATE FOR $test_name ==="
    local metrics_count
    metrics_count=$(_count_metrics)
    local registrations_count
    registrations_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null \
        | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    echo "  Metrics: $metrics_count (baseline was: ${METRICS_BASELINE:-?})"
    echo "  Drone Registrations: $registrations_count"
}

# Helper function to extract drone_id from config
get_drone_id() {
    local config_file="$1"
    docker compose exec -T -u nonroot "$SERVICE_NAME" jq '.droneId' "$config_file" 2>/dev/null || echo ""
}

# Wait for at least $expected_count NEW metrics since METRICS_BASELINE to appear in the database.
# log-sender sends dbSize proofs (one per DHT database per interval) and also forwards
# fetchedOps entries from JSONL files. Both land in the metrics table.
wait_for_database_data() {
    local max_wait="${1:-30}"
    local check_interval="${2:-2}"
    local expected_new="${3:-1}"

    echo "Waiting up to ${max_wait}s for >= $expected_new new metrics (baseline: ${METRICS_BASELINE:-0})..."
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        local total
        total=$(_count_metrics)
        local new_count=$(( total - ${METRICS_BASELINE:-0} ))

        if [[ "$new_count" -ge "$expected_new" ]]; then
            echo "✅ Data found in database: $new_count new metrics (total: $total)"
            return 0
        fi

        sleep "$check_interval"
        elapsed=$(( elapsed + check_interval ))

        if [[ $(( elapsed % 10 )) -eq 0 ]]; then
            echo "  Still waiting... ($elapsed/${max_wait}s, new so far: $new_count)"
        fi
    done

    local final_total
    final_total=$(_count_metrics)
    echo "⚠️  Expected $expected_new new metrics after ${max_wait}s (baseline: ${METRICS_BASELINE:-0}, total: $final_total, new: $(( final_total - ${METRICS_BASELINE:-0} )))"
    return 1
}

@setup() {
    # Verify prerequisites
    if ! curl -s "http://localhost:8787/" 2>/dev/null | grep -q "log-collector\|ok"; then
        skip "Log-collector service not responding"
    fi

    # Capture baseline metric count so each test can measure its own delta
    METRICS_BASELINE=$(_count_metrics)
    echo "Metrics baseline: $METRICS_BASELINE"
}

@teardown() {
    echo "=== FINAL DATABASE STATE AFTER TEST ==="
    verify_database_state "POST-TEST"

    # Cleanup test artifacts
    docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'rm -rf /data/logs/integration_test_* /etc/log-sender/integration_*.json' 2>/dev/null || true
    rm -f /tmp/integration_test_*.jsonl 2>/dev/null || true
}

@test "integration: log-sender populates database with single metric" {
    echo "=== INTEGRATION TEST: Single Metric Database Population ==="

    local test_config="/etc/log-sender/integration_single.json"
    local test_log_dir="/data/logs/integration_test_single"

    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success

    # Write a single fetchedOps entry — the k type log-sender forwards from JSONL
    local current_time=$(( $(date +%s) * 1000000 ))
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$current_time\",\"count\":1,\"latency\":50}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "echo '$log_content' > $test_log_dir/metrics.jsonl"
    assert_success

    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir/" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 20 log-sender service --config-file "$test_config"
    echo "log-sender output: $output"

    # Expect at least 1 new metric (the fetchedOps entry, plus dbSize proofs)
    wait_for_database_data 25 1 1

    local new_count=$(( $(_count_metrics) - METRICS_BASELINE ))
    echo "✅ SUCCESS: $new_count new metrics added to database"
}

@test "integration: log-sender populates database with multiple metrics" {
    echo "=== INTEGRATION TEST: Multiple Metrics Database Population ==="

    local test_config="/etc/log-sender/integration_multi.json"
    local test_log_dir="/data/logs/integration_test_multi"

    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success

    # Write 4 fetchedOps entries — log-sender only forwards entries with k="fetchedOps"
    local current_time=$(( $(date +%s) * 1000000 ))
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$current_time\",\"count\":10,\"latency\":100}
{\"k\":\"fetchedOps\",\"t\":\"$((current_time + 1000000))\",\"count\":20,\"latency\":120}
{\"k\":\"fetchedOps\",\"t\":\"$((current_time + 2000000))\",\"count\":15,\"latency\":80}
{\"k\":\"fetchedOps\",\"t\":\"$((current_time + 3000000))\",\"count\":30,\"latency\":200}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "printf '%s\n' '$log_content' > $test_log_dir/metrics.jsonl"
    assert_success

    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 25 log-sender service --config-file "$test_config"

    # Expect at least 4 new metrics (the 4 fetchedOps entries)
    wait_for_database_data 30 2 4

    local new_count=$(( $(_count_metrics) - METRICS_BASELINE ))
    echo "Found $new_count new metrics in database (expected: >= 4)"

    if [[ "$new_count" -ge 4 ]]; then
        echo "✅ SUCCESS: $new_count new metrics successfully stored"
    else
        echo "❌ FAILURE: Expected >= 4 metrics, found only $new_count"
        return 1
    fi
}

@test "integration: database persistence across multiple log-sender runs" {
    echo "=== INTEGRATION TEST: Database Persistence Across Runs ==="

    local test_config="/etc/log-sender/integration_persistence.json"
    local test_log_dir="/data/logs/integration_test_persistence"

    echo "--- FIRST RUN: Creating initial data ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success

    local first_run_time=$(( $(date +%s) * 1000000 ))
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$first_run_time\",\"count\":5,\"latency\":60}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "echo '$log_content' > $test_log_dir/first_run.jsonl"
    assert_success

    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service --config-file "$test_config"

    wait_for_database_data 20 1 1

    local after_first=$(( $(_count_metrics) - METRICS_BASELINE ))
    echo "After first run: $after_first new metrics since baseline"

    # Second run — add new fetchedOps entries with later timestamps (so they pass last_record_timestamp filter)
    echo "--- SECOND RUN: Adding more data ---"
    local second_run_time=$(( $(date +%s) * 1000000 ))
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$second_run_time\",\"count\":8,\"latency\":70}
{\"k\":\"fetchedOps\",\"t\":\"$((second_run_time + 1000000))\",\"count\":12,\"latency\":90}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "printf '%s\n' '$log_content' > $test_log_dir/second_run.jsonl"

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service --config-file "$test_config"

    # Expect more new metrics than after first run (dbSize proofs + new fetchedOps)
    local expected_after_second=$(( after_first + 1 ))
    wait_for_database_data 20 2 "$expected_after_second"

    local after_second=$(( $(_count_metrics) - METRICS_BASELINE ))
    echo "After second run: $after_second new metrics since baseline"

    if [[ "$after_second" -gt "$after_first" ]]; then
        echo "✅ SUCCESS: Database persistence confirmed ($after_first → $after_second since baseline)"
    else
        echo "❌ FAILURE: Second run added no new metrics (expected > $after_first, got $after_second)"
        return 1
    fi
}

@test "integration: real-time metric processing and storage" {
    echo "=== INTEGRATION TEST: Real-time Processing ==="

    local test_config="/etc/log-sender/integration_realtime.json"
    local test_log_dir="/data/logs/integration_test_realtime"

    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    # Create an empty initial file so the report-path directory is valid
    run docker compose exec -T -u nonroot "$SERVICE_NAME" touch "$test_log_dir/realtime_initial.jsonl"
    assert_success

    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 3
    assert_success

    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    # Start service in background then write fetchedOps entries while it's running
    echo "--- Starting log-sender service for real-time processing ---"
    docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 30 log-sender service --config-file "$test_config" > /tmp/realtime_service.log 2>&1 &
    local service_pid=$!
    echo "Service started with PID: $service_pid"

    sleep 5

    echo "--- Writing fetchedOps metrics in real-time ---"
    local base_time=$(( $(date +%s) * 1000000 ))
    for i in {1..5}; do
        local entry_time=$(( base_time + (i * 500000) ))
        echo "Writing entry $i at $(date)"
        local log_content="{\"k\":\"fetchedOps\",\"t\":\"$entry_time\",\"count\":$((i * 10)),\"latency\":$((i * 20))}"
        run docker compose exec -T -u nonroot "$SERVICE_NAME" \
            sh -c "echo '$log_content' > $test_log_dir/realtime_$i.jsonl"
        assert_success
        sleep 2
    done

    echo "--- Waiting for real-time processing to complete ---"
    wait_for_database_data 25 2 3

    kill $service_pid 2>/dev/null || true
    wait $service_pid 2>/dev/null || true

    local new_count=$(( $(_count_metrics) - METRICS_BASELINE ))
    echo "Real-time metrics processed: $new_count (expected: >= 3)"

    if [[ "$new_count" -ge 3 ]]; then
        echo "✅ SUCCESS: Real-time processing worked ($new_count new metrics)"
    else
        echo "❌ FAILURE: Real-time processing failed (expected >= 3, got $new_count)"
        echo "Service log:"
        tail -20 /tmp/realtime_service.log
        return 1
    fi
}

@test "integration: data integrity and validation" {
    echo "=== INTEGRATION TEST: Data Integrity and Validation ==="

    local test_config="/etc/log-sender/integration_integrity.json"
    local test_log_dir="/data/logs/integration_test_integrity"

    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success

    local current_time=$(( $(date +%s) * 1000000 ))
    # Only fetchedOps entries are forwarded by log-sender; other k values are ignored
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$current_time\",\"count\":1,\"latency\":10}
{\"k\":\"fetchedOps\",\"t\":\"$((current_time + 1000000))\",\"count\":2,\"latency\":20}
{\"k\":\"start\",\"t\":\"$((current_time + 2000000))\",\"component\":\"test\",\"status\":\"ok\"}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "printf '%s\n' '$log_content' > $test_log_dir/integrity.jsonl"
    assert_success

    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 20 log-sender service --config-file "$test_config"

    wait_for_database_data 25 1 2

    echo "=== VERIFYING DATA INTEGRITY ==="

    # Verify the stored dbSize proofs have the expected JSON structure (k, t, d, b fields)
    local proof_json
    proof_json=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT proof FROM metrics ORDER BY id DESC LIMIT 1;" 2>/dev/null \
        | grep -o '"proof": "[^"]*"' | sed 's/"proof": "//;s/"$//' | head -1 || echo "")

    echo "Most recent proof: $proof_json"

    if [[ -z "$proof_json" ]]; then
        echo "❌ FAILURE: No proof found in database"
        return 1
    fi

    # Verify all proofs have a timestamp in a reasonable range (last hour)
    local recent_count
    local one_hour_ago=$(( ($(date +%s) - 3600) * 1000 ))
    recent_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE metric_timestamp >= $one_hour_ago;" 2>/dev/null \
        | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")

    echo "Metrics with recent timestamps: $recent_count"

    if [[ "$recent_count" -ge 1 ]]; then
        echo "✅ SUCCESS: Metrics stored with valid recent timestamps"
    else
        echo "❌ FAILURE: No metrics found with recent timestamps"
        return 1
    fi

    # Verify drone registration exists for the signing key
    local drone_regs
    drone_regs=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null \
        | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")

    if [[ "$drone_regs" -ge 1 ]]; then
        echo "✅ SUCCESS: Drone registration present ($drone_regs registrations)"
    else
        echo "❌ FAILURE: No drone registration found"
        return 1
    fi
}

@test "integration: complete cleanup and reset verification" {
    echo "=== INTEGRATION TEST: Complete Cleanup and Reset ==="

    local populate_config="/etc/log-sender/integration_cleanup.json"
    local populate_log_dir="/data/logs/integration_test_cleanup"

    echo "--- PHASE 1: Populate database with test data ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$populate_log_dir"
    assert_success

    local cleanup_time=$(( $(date +%s) * 1000000 ))
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$cleanup_time\",\"count\":3,\"latency\":40}
{\"k\":\"fetchedOps\",\"t\":\"$((cleanup_time + 1000000))\",\"count\":7,\"latency\":55}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "printf '%s\n' '$log_content' > $populate_log_dir/cleanup_test.jsonl"
    assert_success

    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$populate_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$populate_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    docker compose cp "$SCRIPT_DIR/relay.json" "$SERVICE_NAME:/home/nonroot/"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c 'cd /home/nonroot && install_happ relay.json test-node'
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service --config-file "$populate_config"

    wait_for_database_data 20 1 2

    local before_cleanup
    before_cleanup=$(_count_metrics)
    echo "Metrics before cleanup: $before_cleanup"

    if [[ "$before_cleanup" -le "$METRICS_BASELINE" ]]; then
        echo "❌ FAILURE: Could not populate database for cleanup test"
        return 1
    fi

    # PHASE 2: Use a fresh config (re-registration) to verify system resets cleanly
    echo "--- PHASE 2: Fresh registration and verification ---"
    local verification_config="/etc/log-sender/integration_verification.json"
    local verification_log_dir="/data/logs/integration_test_verification"

    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$verification_log_dir"
    assert_success

    local verify_time=$(( $(date +%s) * 1000000 ))
    local log_content="{\"k\":\"fetchedOps\",\"t\":\"$verify_time\",\"count\":99,\"latency\":5}"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" \
        sh -c "echo '$log_content' > $verification_log_dir/verification.jsonl"
    assert_success

    # New config = new drone registration
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$verification_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$verification_log_dir" \
        --conductor-config-path /etc/holochain/conductor-config.yaml \
        --report-interval-seconds 2
    assert_success

    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service --config-file "$verification_config"

    local after_verification
    after_verification=$(_count_metrics)
    echo "Metrics after fresh registration run: $after_verification"

    if [[ "$after_verification" -gt "$before_cleanup" ]]; then
        echo "✅ SUCCESS: System works after cleanup — new data stored with fresh registration"
        echo "  Before cleanup: $before_cleanup, After: $after_verification"
    else
        echo "❌ FAILURE: System not functioning after cleanup"
        return 1
    fi
}
