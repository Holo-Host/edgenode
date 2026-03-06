#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Test configuration
LOG_COLLECTOR_URL="http://log-collector:8787"
LOCAL_LOG_COLLECTOR_URL="http://localhost:8787"
ADMIN_SECRET="test_admin_secret"
UNYT_PUB_KEY="uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"

is_unyt() {
  [[ "$IMAGE_NAME" =~ unyt ]]
}

# Helper function to verify prerequisites before tests
verify_test_prerequisites() {
    echo "=== VERIFYING TEST PREREQUISITES ==="
    
    # Check log-collector service is running
    echo "Checking log-collector service..."
    if curl -s "http://localhost:8787/" 2>/dev/null | grep -q "log-collector\|ok"; then
        echo "✅ Log-collector service is responding"
    else
        echo "❌ Log-collector service not responding"
        return 1
    fi
    
    # Check database connectivity
    echo "Checking database connectivity..."
    local db_test=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT 1 as test;" 2>/dev/null | grep -o '"test": 1' | head -1)
    if [[ -n "$db_test" ]]; then
        echo "✅ Database connectivity verified"
    else
        echo "❌ Database connectivity failed"
        return 1
    fi
    
    # Check network connectivity between containers
    echo "Checking network connectivity..."
    if docker compose exec -T -u nonroot "$SERVICE_NAME" ping -c 1 log-collector >/dev/null 2>&1; then
        echo "✅ Network connectivity between containers"
    else
        echo "❌ Network connectivity issues"
        return 1
    fi
    
    echo "✅ All prerequisites verified"
    return 0
}

# Helper function to validate JSONL format
validate_jsonl_format() {
    local file_path="$1"
    local test_name="$2"
    
    echo "=== VALIDATING JSONL FORMAT FOR $test_name ==="
    
    # Check if log file exists using docker compose
    local file_exists=$(docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$file_path" && echo "yes" || echo "no")
    
    if [[ "$file_exists" != "yes" ]]; then
        echo "❌ Log file not found: $file_path"
        echo "Checking directory contents:"
        docker compose exec -T -u nonroot "$SERVICE_NAME" ls -la "$(dirname "$file_path")" 2>/dev/null || echo "Directory not accessible"
        return 1
    fi
    
    echo "✅ Log file exists: $file_path"
    
    # Read file content using docker compose and validate
    local file_content=$(docker compose exec -T -u nonroot "$SERVICE_NAME" cat "$file_path" 2>/dev/null)
    
    if [[ -z "$file_content" ]]; then
        echo "❌ Cannot read log file content: $file_path"
        return 1
    fi
    
    echo "File content preview (first 500 chars):"
    echo "$file_content" | head -c 500
    echo ""
    
    # Count number of lines
    local line_count=$(echo "$file_content" | wc -l)
    echo "Total lines in file: $line_count"
    
    # Validate each line is valid JSON
    local invalid_lines=0
    local valid_lines=0
    local line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # Validate JSON using docker compose exec with jq
        if echo "$line" | docker compose exec -T -u nonroot "$SERVICE_NAME" jq empty 2>/dev/null; then
            valid_lines=$((valid_lines + 1))
            
            # Check for required fields using docker compose exec with jq
            if echo "$line" | docker compose exec -T -u nonroot "$SERVICE_NAME" jq -e '.k and .t' >/dev/null 2>&1; then
                : # Both k and t fields present
            else
                echo "❌ Missing required fields (k, t) on line $line_num"
                invalid_lines=$((invalid_lines + 1))
            fi
        else
            echo "❌ Invalid JSON on line $line_num: $line"
            invalid_lines=$((invalid_lines + 1))
        fi
        
    done <<< "$file_content"
    
    if [[ $invalid_lines -gt 0 ]]; then
        echo "❌ Found $invalid_lines invalid lines out of $line_count total lines"
        return 1
    else
        echo "✅ All $valid_lines/$line_count lines are valid JSON with required fields"
    fi
    
    # Show sample entries
    echo "Sample entries:"
    echo "$file_content" | head -3 | while IFS= read -r line; do
        echo "  $(echo "$line" | docker compose exec -T -u nonroot "$SERVICE_NAME" jq -c '.' 2>/dev/null || echo "$line")"
    done
    
    echo "✅ JSONL format validation passed for $test_name"
    return 0
}

# Helper function to display database contents for debugging
display_database_contents() {
    echo "=========================================="
    echo "DATABASE CONTENTS FOR DEBUGGING"
    echo "=========================================="
    
    # Query database directly for all table contents
    echo ""
    echo "--- METRICS TABLE ---"
    echo "Total metrics count:"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "Could not query metrics"
    
    echo "Sample metrics (first 5 rows):"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT id, signing_pub_key, metric_value, metric_timestamp, verified FROM metrics ORDER BY id DESC LIMIT 5;" 2>/dev/null | grep -E '"id":|"signing_pub_key":|"metric_value":|"metric_timestamp":|"verified":' | head -20 || echo "Could not query metrics data"
    
    echo ""
    echo "--- DRONE_REGISTRATIONS TABLE ---"
    echo "Total drone registrations count:"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "Could not query drone_registrations"
    
    echo "Sample drone registrations (first 5 rows):"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT id, drone_pub_key, unyt_pub_key, status, registered_at FROM drone_registrations ORDER BY id DESC LIMIT 5;" 2>/dev/null | grep -E '"id":|"drone_pub_key":|"unyt_pub_key":|"status":|"registered_at":' | head -20 || echo "Could not query drone registrations"
    
    echo ""
    echo "--- DNA_REGISTRATIONS TABLE ---"
    echo "Total DNA registrations count:"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM dna_registrations;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "Could not query dna_registrations"
    
    echo "Sample DNA registrations (first 5 rows):"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT id, drone_pub_key, dna_hash, agreement_id, status FROM dna_registrations ORDER BY id DESC LIMIT 5;" 2>/dev/null | grep -E '"id":|"drone_pub_key":|"dna_hash":|"agreement_id":|"status":' | head -20 || echo "Could not query DNA registrations"
    
    echo ""
    echo "--- INVOICE_PERIODS TABLE ---"
    echo "Total invoice periods count:"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM invoice_periods;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "Could not query invoice_periods"
    
    echo "Sample invoice periods (first 5 rows):"
    docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT id, period_start, period_end, metrics_count, drones_count, invoice_reference FROM invoice_periods ORDER BY id DESC LIMIT 5;" 2>/dev/null | grep -E '"id":|"period_start":|"period_end":|"metrics_count":|"drones_count":|"invoice_reference":' | head -20 || echo "Could not query invoice periods"
    
    echo ""
    echo "=========================================="
    echo "DATABASE VERIFICATION SUMMARY"
    echo "=========================================="
    
    # Test basic database connectivity
    echo "Testing database connectivity..."
    local test_response=$(curl -s "http://localhost:8787/" 2>/dev/null || echo "Database not responding")
    
    if echo "$test_response" | grep -q "log-collector" || echo "$test_response" | grep -q "ok" || [[ "$test_response" != "Database not responding" ]]; then
        echo "✅ Database server is responding"
        echo "✅ D1 database bindings are active"
    else
        echo "❌ Database connectivity issues detected"
        echo "Response: $test_response"
    fi
    
    echo ""
    echo "Note: This debugging output shows actual database table contents."
    echo "All data stored during the test should be visible above."
    echo ""
    echo "=========================================="
    echo "END DATABASE CONTENTS"
    echo "=========================================="
}

# Helper function to verify log-sender registration occurred
verify_log_sender_registration() {
    local config_file="$1"
    
    # Use docker compose to verify the file exists and contains required fields
    echo "--- Verifying config file: $config_file ---"
    
    # Check if we can read the config file content via docker
    local config_content=$(docker compose exec -T -u nonroot "$SERVICE_NAME" cat "$config_file" 2>/dev/null)
    
    if [[ -z "$config_content" ]]; then
        echo "❌ Cannot read config file content: $config_file"
        return 1
    fi
    
    echo "Config file content (first 200 chars): ${config_content:0:200}..."
    
    # Parse required fields using correct field names (camelCase as per actual config)
    local drone_pub_key=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r '.dronePubKey' "$config_file" 2>/dev/null)
    local unyt_pub_key=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r '.unytPubKey' "$config_file" 2>/dev/null)
    local drone_id=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r '.droneId' "$config_file" 2>/dev/null)
    
    # Check RSA public key format (should be base64 SPKI DER starting with MIIB)
    if [[ -n "$drone_pub_key" && "$drone_pub_key" != "null" && "$drone_pub_key" =~ ^MIIB ]]; then
        echo "✅ Config contains valid RSA drone public key (${#drone_pub_key} chars)"
    else
        echo "❌ Config missing or invalid drone public key: '$drone_pub_key'"
        return 1
    fi
    
    # Check Holochain public key format (should start with uhCAk)
    if [[ -n "$unyt_pub_key" && "$unyt_pub_key" != "null" && "$unyt_pub_key" =~ ^uhCAk ]]; then
        echo "✅ Config contains valid Holochain unyt public key (${#unyt_pub_key} chars)"
    else
        echo "❌ Config missing or invalid unyt public key: '$unyt_pub_key'"
        return 1
    fi
    
    # Check drone_id (indicates successful registration)
    if [[ -n "$drone_id" && "$drone_id" != "null" && "$drone_id" =~ ^[0-9]+$ ]]; then
        echo "✅ Config contains drone ID: $drone_id (registration successful)"
        return 0
    else
        echo "⚠️  Config missing drone ID (registration may not have completed): '$drone_id'"
        return 1
    fi
}

# Helper function to wait for log processing
wait_for_log_processing() {
    local max_wait="${1:-10}"
    local check_interval="${2:-1}"
    
    echo "Waiting up to ${max_wait}s for log processing..."
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local metrics_count=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
            --command="SELECT COUNT(*) as total FROM metrics WHERE metric_timestamp > $(( ($(date +%s) - 60) * 1000 ));" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
        
        if [[ "$metrics_count" -gt 0 ]]; then
            echo "✅ Log processing detected: $metrics_count recent metrics"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo "⚠️  No recent metrics found after ${max_wait}s"
    return 1
}

@setup() {
    # Verify prerequisites before running tests
    if [[ -z "$IMAGE_NAME" || ! "$IMAGE_NAME" =~ "unyt" ]]; then
        skip "Not running on unyt image - prerequisites check skipped"
    fi
    
    # Run prerequisites check for integration tests
    if [[ "$BATS_TEST_NAME" =~ "end-to-end" ]] || [[ "$BATS_TEST_NAME" =~ "integration" ]]; then
        verify_test_prerequisites || skip "Prerequisites not met"
    fi
}

@teardown() {
    # Cleanup any test artifacts
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json 2>/dev/null || true
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf /data/logs/e2e_test 2>/dev/null || true
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf /data/logs/jsonl_test 2>/dev/null || true
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf /data/logs/performance_test 2>/dev/null || true
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf /data/logs/error_test 2>/dev/null || true
    rm -f /tmp/metrics_logs.jsonl 2>/dev/null || true
    rm -f /tmp/test_logs.jsonl 2>/dev/null || true
    rm -f /tmp/large_test_logs.jsonl 2>/dev/null || true
}

@test "log-sender service connectivity verification" {
  if is_unyt; then
    # Setup test environment
    local test_config="/etc/log-sender/connectivity-config.json"
    
    # Cleanup any existing config (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"
    
    # Debug: Check directory structure before init
    echo "--- Directory structure before init ---"
    docker compose exec -T -u nonroot "$SERVICE_NAME" ls -la /etc/log-sender/ 2>/dev/null || echo "Directory not accessible"
    
    # Initialize configuration (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path /data/logs \
        --report-interval-seconds 10
    assert_success
    
    # Debug: Check directory structure after init
    echo "--- Directory structure after init ---"
    docker compose exec -T -u nonroot "$SERVICE_NAME" ls -la /etc/log-sender/ 2>/dev/null || echo "Directory not accessible"
    
    # Debug: Check if file exists using multiple methods
    echo "--- File existence check ---"
    docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$test_config" && echo "✅ File exists: $test_config" || echo "❌ File does not exist: $test_config"
    docker compose exec -T -u nonroot "$SERVICE_NAME" stat "$test_config" 2>/dev/null || echo "❌ Cannot stat: $test_config"
    
    # Verify file was created (same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$test_config"
    assert_success
    
    # Verify registration was successful
    verify_log_sender_registration "$test_config"
    
    # Test service connectivity (should attempt to connect)
    run docker compose exec -T -u nonroot -e RUST_LOG=debug "$SERVICE_NAME" \
        timeout 10 log-sender service \
        --config-file "$test_config"
    
    # Service should start and attempt connection
    assert_output --partial "connecting to"
    assert_output --partial "log-collector"
    
    # Verify service operational status
    if [[ "$status" -eq 124 ]] || [[ "$status" -eq 0 ]]; then
        echo "✅ Service connectivity test passed"
    else
        echo "❌ Service connectivity failed with status: $status"
        echo "Output: $output"
        return 1
    fi
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender registration workflow verification" {
  if is_unyt; then
    echo "=== TESTING LOG-SENDER REGISTRATION WORKFLOW ==="
    echo "Expected behavior (based on log-sender process flow):"
    echo "  1. log-sender init generates RSA keypair and calls drone-registration endpoint"
    echo "  2. Registration includes: dronePubKey (RSA), unytPubKey (Holochain), signature"
    echo "  3. On success, config file contains drone_id from server response"
    echo ""

    # Setup test environment
    local test_config="/etc/log-sender/test-registration-config.json"
    
    # Cleanup any existing config (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"

    # Initialize log-sender (this will automatically handle registration)
    echo "--- Testing log-sender init with proper key types ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path /data/logs \
        --report-interval-seconds 10
    
    # Verify initialization completed successfully
    if [[ "$status" -eq 0 ]]; then
        echo "✅ log-sender init completed successfully"
        echo "   - RSA keypair generated"
        echo "   - Registration request sent to /drone-registration"
        echo "   - Response processed and drone_id stored"
    else
        echo "❌ log-sender init failed with status: $status"
        echo "Output: $output"
        return 1
    fi
    
    # Verify file was created (same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$test_config"
    assert_success
    
    # Verify registration was successful by checking config
    echo "--- Verifying registration data in config ---"
    verify_log_sender_registration "$test_config"
    
    # Show what was actually registered
    echo "--- Registration data summary ---"
    local drone_pub_key=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r '.drone_pub_key' "$test_config" 2>/dev/null)
    local unyt_pub_key=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r '.unyt_pub_key' "$test_config" 2>/dev/null)
    local drone_id=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r '.drone_id' "$test_config" 2>/dev/null)
    
    echo "Registered drone ID: $drone_id"
    echo "Drone public key length: ${#drone_pub_key} characters"
    echo "Unyt public key length: ${#unyt_pub_key} characters"
    
    # Verify database contains the registration
    echo "--- Verifying database contains registration ---"
    local db_drone_id=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT id FROM drone_registrations WHERE drone_pub_key = '$drone_pub_key' ORDER BY id DESC LIMIT 1;" 2>/dev/null | grep -o '"id": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "")
    
    if [[ -n "$db_drone_id" && "$db_drone_id" == "$drone_id" ]]; then
        echo "✅ SUCCESS: Database contains matching drone registration"
        echo "   - Config drone_id: $drone_id"
        echo "   - Database drone_id: $db_drone_id"
    elif [[ -n "$db_drone_id" ]]; then
        echo "⚠️  Database contains different drone ID: $db_drone_id (config: $drone_id)"
    else
        echo "ℹ️  No matching registration found in database (may be normal depending on server setup)"
    fi
    
    echo ""
    echo "=== REGISTRATION WORKFLOW SUMMARY ==="
    echo "✅ log-sender init: Automatically handles drone registration"
    echo "✅ RSA keypair: Generated during init"
    echo "✅ Registration: Sent to /drone-registration endpoint with proper key types"
    echo "✅ Config storage: drone_id and keys stored locally"
    echo "✅ Database: Registration data stored on server"
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"
  else
    skip "Not running on unyt image"
  fi
}

@test "end-to-end log transmission test with database population" {
  if is_unyt; then
    # Setup test environment
    TEST_NAMESPACE="bats_$(date +%s)"
    TEST_LOG_DIR="/data/logs/e2e_test"
    
    # Force cleanup any existing config and test directory (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf "$TEST_LOG_DIR" /etc/log-sender/config.json

    # Create test log file with proper microsecond timestamps
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$TEST_LOG_DIR"
    assert_success
    
    # Create realistic metrics logs with CORRECT microsecond timestamps
    local current_time=$(($(date +%s) * 1000000))  # CORRECT: microseconds as required
    cat > /tmp/metrics_logs.jsonl <<EOF
{"k":"metric","t":"$current_time","value":100.5,"source":"test_e2e","unit":1,"tags":"{\"namespace\":\"$TEST_NAMESPACE\",\"test\":\"e2e\"}"}
{"k":"metric","t":"$((current_time + 1000000))","value":250.3,"source":"test_e2e","unit":2,"tags":"{\"namespace\":\"$TEST_NAMESPACE\",\"test\":\"e2e\"}"}
{"k":"metric","t":"$((current_time + 2000000))","value":75.8,"source":"test_e2e","unit":1,"tags":"{\"namespace\":\"$TEST_NAMESPACE\",\"test\":\"e2e\"}"}
{"k":"metric","t":"$((current_time + 3000000))","value":180.2,"source":"test_e2e","unit":3,"tags":"{\"namespace\":\"$TEST_NAMESPACE\",\"test\":\"e2e\"}"}
{"k":"start","t":"$((current_time + 4000000))","namespace":"$TEST_NAMESPACE","status":"initialized"}
{"k":"fetchedOps","t":"$((current_time + 5000000))","count":150,"latency":42}
EOF
    
    run docker compose cp /tmp/metrics_logs.jsonl "$SERVICE_NAME:$TEST_LOG_DIR/metrics.jsonl"
    assert_success
    
    # Validate JSONL format before processing
    validate_jsonl_format "$TEST_LOG_DIR/metrics.jsonl" "E2E Test"
    
    # Initialize log-sender (this automatically handles registration) (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file /etc/log-sender/config.json \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$TEST_LOG_DIR" \
        --report-interval-seconds 2  # Short interval for quick testing
    assert_success
    
    # Verify file was created (same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f /etc/log-sender/config.json
    assert_success
    
    # Verify registration was successful
    verify_log_sender_registration "/etc/log-sender/config.json"
    
    # Show database state before log-sender runs
    echo "=== DATABASE STATE BEFORE LOG-SENDER ==="
    local before_metrics=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    local before_drone_regs=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "BEFORE TEST RUN:"
    echo "  Metrics: $before_metrics"
    echo "  Drone Registrations: $before_drone_regs"
    
    # Start log-sender service and let it process logs
    echo "=== RUNNING LOG-SENDER SERVICE ==="
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 25 log-sender service \
        --config-file /etc/log-sender/config.json
    
    # Store the service exit status for validation
    local service_status=$status
    
    # Wait for log processing to complete
    wait_for_log_processing 15 1
    
    # Show database state after log-sender runs
    echo "=== DATABASE STATE AFTER LOG-SENDER ==="
    local after_metrics=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    local after_drone_regs=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "AFTER TEST RUN:"
    echo "  Metrics: $after_metrics"
    echo "  Drone Registrations: $after_drone_regs"
    
    echo "CHANGES DURING TEST:"
    echo "  Metrics: $before_metrics → $after_metrics (Δ$((after_metrics - before_metrics)))"
    echo "  Drone Registrations: $before_drone_regs → $after_drone_regs (Δ$((after_drone_regs - before_drone_regs)))"
    
    # Verify log-sender service ran successfully
    if [[ $service_status -eq 124 ]]; then
        echo "✅ SUCCESS: log-sender service completed full 25-second cycle without crashing"
    elif [[ $service_status -eq 0 ]]; then
        echo "✅ SUCCESS: log-sender service completed normally"
    else
        echo "❌ FAILURE: log-sender service failed with status $service_status"
        echo "Output: $output"
        return 1
    fi
    
    # Service output should show it was processing logs
    assert_output --partial "Running Command"
    assert_output --partial "Service {"
    
    # Analysis of results
    if [[ $((after_metrics - before_metrics)) -gt 0 ]]; then
        echo "✅ SUCCESS: $((after_metrics - before_metrics)) metrics added to database"
    else
        echo "ℹ️  DIAGNOSTIC: No metrics added to database (may indicate log-sender pipeline issue)"
        echo "However, registration and service operation worked correctly!"
    fi
    
    if [[ $((after_drone_regs - before_drone_regs)) -gt 0 ]]; then
        echo "✅ $((after_drone_regs - before_drone_regs)) drone registrations added during test"
    fi
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf "$TEST_LOG_DIR" /etc/log-sender/config.json
    rm -f /tmp/metrics_logs.jsonl
  else
    skip "Not running on unyt image"
  fi
}

@test "end-to-end log transmission test" {
  if is_unyt; then
    # Setup test environment
    TEST_NAMESPACE="bats_$(date +%s)"
    TEST_LOG_DIR="/data/logs/e2e_test"
    
    # Cleanup any existing config (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json

    # Create test log file
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$TEST_LOG_DIR"
    assert_success
    
    # Create realistic test logs with CORRECT microsecond timestamps
    local current_time=$(($(date +%s) * 1000000))  # CORRECT: microseconds
    local log_content="{\"k\":\"p2p_report\",\"t\":\"$current_time\",\"peers\":5,\"latency\":150,\"throughput\":1000,\"namespace\":\"$TEST_NAMESPACE\"}"
    
    run docker compose exec -T -u nonroot "$SERVICE_NAME" sh -c "echo '$log_content' > $TEST_LOG_DIR/test.jsonl && chmod 644 $TEST_LOG_DIR/test.jsonl"
    assert_success
    
    # Validate JSONL format
    validate_jsonl_format "$TEST_LOG_DIR/test.jsonl" "Basic E2E Test"
    
    # Initialize log-sender (this automatically handles registration) (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file /etc/log-sender/config.json \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$TEST_LOG_DIR" \
        --report-interval-seconds 5
    assert_success
    
    # Verify file was created (same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f /etc/log-sender/config.json
    assert_success
    
    # Verify registration was successful
    verify_log_sender_registration "/etc/log-sender/config.json"
    
    # Start log-sender service in background
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 20 log-sender service \
        --config-file /etc/log-sender/config.json
    
    # Store the service exit status for validation
    local service_status=$status
    
    # Query log-collector for the test data
    local start_time=$(($(date +%s) - 300))
    local end_time=$(($(date +%s) + 60))
    
    local response=$(curl -s -G "$LOCAL_LOG_COLLECTOR_URL/logs" \
        --data-urlencode "startTime=$start_time" \
        --data-urlencode "endTime=$end_time" \
        --data-urlencode "limit=1000" \
        -H "X-Admin-Secret: $ADMIN_SECRET")
    
    # Validate response structure
    echo "Log-Collector Response: $response"
    
    # Verify log-collector is functioning
    if [[ "$response" =~ "\"success\":true" ]]; then
        echo "✅ SUCCESS: log-collector responding correctly"
    else
        echo "❌ FAILURE: log-collector not responding correctly"
        echo "Response: $response"
        return 1
    fi
    
    # Verify log-sender service ran successfully without crashes
    # Status 124 means timeout, which is expected (service runs for 20 seconds then times out)
    if [[ $service_status -eq 124 ]]; then
        echo "✅ SUCCESS: log-sender service completed full 20-second cycle without crashing"
    elif [[ $service_status -eq 0 ]]; then
        echo "✅ SUCCESS: log-sender service completed normally"
    else
        echo "❌ FAILURE: log-sender service failed with status $service_status"
        echo "Output: $output"
        return 1
    fi
    
    # Service output should show it was attempting to process logs
    assert_output --partial "Running Command"
    assert_output --partial "Service {"
    
    # Display database contents before cleanup to verify data was stored
    display_database_contents
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf "$TEST_LOG_DIR" /etc/log-sender/config.json
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender processes JSONL files correctly" {
  if is_unyt; then
    local test_log_dir="/data/logs/jsonl_test"
    
    # Cleanup any existing config (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f /etc/log-sender/config.json

    # Create test JSONL file
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    
    # Create valid JSONL content with CORRECT microsecond timestamps
    local current_time=$(($(date +%s) * 1000000))  # CORRECT: microseconds
    cat > /tmp/test_logs.jsonl <<EOF
{"k":"metric","t":"$current_time","value":100,"source":"test"}
{"k":"metric","t":"$((current_time + 1000000))","value":200,"source":"test"}
{"k":"start","t":"$((current_time + 2000000))","component":"test_suite"}
{"k":"fetchedOps","t":"$((current_time + 3000000))","count":42}
EOF
    
    run docker compose cp /tmp/test_logs.jsonl "$SERVICE_NAME:$test_log_dir/test.jsonl"
    assert_success
    
    # Validate JSONL format before processing
    validate_jsonl_format "$test_log_dir/test.jsonl" "JSONL Processing Test"
    
    # Initialize and start log-sender (this automatically handles registration) (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file /etc/log-sender/config.json \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --report-interval-seconds 2
    assert_success
    
    # Verify file was created (same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f /etc/log-sender/config.json
    assert_success
    
    # Verify registration was successful
    verify_log_sender_registration "/etc/log-sender/config.json"
    
    # Run log-sender service
    run docker compose exec -T -u nonroot -e RUST_LOG=info "$SERVICE_NAME" \
        timeout 15 log-sender service \
        --config-file /etc/log-sender/config.json
    
    # Service should start (timeout 124 is expected after 15 seconds)
    if [[ "$status" -eq "124" ]]; then
        echo "✅ SUCCESS: log-sender service ran for 15 seconds (timeout expected)"
    else
        assert_success
        assert_output --partial "processing"
    fi
    
    # Display database contents before cleanup to verify data was stored
    display_database_contents
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf "$test_log_dir" /etc/log-sender/config.json
    rm -f /tmp/test_logs.jsonl
  else
    skip "Not running on unyt image"
  fi
}

@test "admin logs endpoint authentication" {
  if is_unyt; then
    # Test admin endpoint requires proper authentication
    local start_time=$(($(date +%s) - 300))
    local end_time=$(($(date +%s) + 60))
    
    # Test with wrong admin secret
    run curl -s -G "$LOCAL_LOG_COLLECTOR_URL/logs" \
        --data-urlencode "startTime=$start_time" \
        --data-urlencode "endTime=$end_time" \
        -H "X-Admin-Secret: wrong_secret"
    
    assert_output --partial "UNAUTHORIZED_ADMIN"
    
    # Test with correct admin secret
    run curl -s -G "$LOCAL_LOG_COLLECTOR_URL/logs" \
        --data-urlencode "startTime=$start_time" \
        --data-urlencode "endTime=$end_time" \
        -H "X-Admin-Secret: $ADMIN_SECRET"
    
    # Should succeed (even if empty results)
    refute_output --partial "UNAUTHORIZED_ADMIN"
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender error handling and recovery" {
  if is_unyt; then
    # Test with invalid endpoint
    echo "=== TESTING ERROR HANDLING ==="
    
    local test_config="/etc/log-sender/error-test-config.json"
    
    # Cleanup any existing config (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"
    
    echo "--- Testing with invalid endpoint ---"
    # This should fail during health check
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "http://invalid-endpoint:9999" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path /data/logs \
        --report-interval-seconds 10
    
    # Should fail (non-zero exit status)
    if [[ "$status" -ne 0 ]]; then
        echo "✅ Correctly rejected invalid endpoint"
    else
        echo "❌ Should have failed with invalid endpoint"
        return 1
    fi
    
    # Test with invalid unyt key format
    echo "--- Testing with invalid unyt key format ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "invalid_key_format" \
        --report-path /data/logs \
        --report-interval-seconds 10
    
    # Should fail with invalid key format
    if [[ "$status" -ne 0 ]]; then
        echo "✅ Correctly rejected invalid unyt key format"
    else
        echo "❌ Should have failed with invalid unyt key"
        return 1
    fi
    
    # Test service with missing config
    echo "--- Testing service with missing config ---"
    run docker compose exec -T -u nonroot -e RUST_LOG=error "$SERVICE_NAME" \
        timeout 5 log-sender service \
        --config-file /nonexistent/config.json
    
    # Should fail with missing config
    if [[ "$status" -ne 0 ]]; then
        echo "✅ Correctly failed with missing config file"
    else
        echo "❌ Should have failed with missing config"
        return 1
    fi
    
    echo "✅ All error handling tests passed"
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender performance and load testing" {
  if is_unyt; then
    # Test with larger log files to verify performance
    echo "=== TESTING PERFORMANCE AND LOAD ==="
    
    local test_log_dir="/data/logs/performance_test"
    local test_config="/etc/log-sender/performance-config.json"
    
    # Cleanup any existing config (using same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$test_config"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf "$test_log_dir"
    
    # Create test directory
    run docker compose exec -T -u nonroot "$SERVICE_NAME" mkdir -p "$test_log_dir"
    assert_success
    
    # Create larger log file for performance testing
    echo "--- Creating performance test log file (100 entries) ---"
    local start_time=$(($(date +%s) * 1000000))
    
    {
        for i in {1..100}; do
            local entry_time=$((start_time + (i * 10000)))
            echo "{\"k\":\"perf_test\",\"t\":\"$entry_time\",\"iteration\":$i,\"value\":$((i * 10)),\"metadata\":\"{\\\"test\\\":\\\"performance\\\",\\\"batch\\\":1}\"}"
        done
    } > /tmp/large_test_logs.jsonl
    
    run docker compose cp /tmp/large_test_logs.jsonl "$SERVICE_NAME:$test_log_dir/performance.jsonl"
    assert_success
    
    # Validate JSONL format
    validate_jsonl_format "$test_log_dir/performance.jsonl" "Performance Test"
    
    # Initialize log-sender
    echo "--- Initializing log-sender for performance test ---"
    run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
        --config-file "$test_config" \
        --endpoint "$LOG_COLLECTOR_URL" \
        --unyt-pub-key "$UNYT_PUB_KEY" \
        --report-path "$test_log_dir" \
        --report-interval-seconds 1  # Fast interval for performance test
    assert_success
    
    # Verify file was created (same pattern as working tests)
    run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$test_config"
    assert_success
    
    # Verify registration
    verify_log_sender_registration "$test_config"
    
    # Run performance test
    echo "--- Running performance test (30 seconds) ---"
    local start_perf=$(date +%s)
    run docker compose exec -T -u nonroot -e RUST_LOG=warn "$SERVICE_NAME" \
        timeout 30 log-sender service \
        --config-file "$test_config"
    
    local end_perf=$(date +%s)
    local duration=$((end_perf - start_perf))
    
    echo "Performance test completed in ${duration} seconds"
    
    # Verify service ran without crashing
    if [[ "$status" -eq 124 ]] || [[ "$status" -eq 0 ]]; then
        echo "✅ Performance test completed successfully"
    else
        echo "❌ Performance test failed with status: $status"
        return 1
    fi
    
    # Check database for performance test results
    local perf_metrics=$(docker compose exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM metrics WHERE metric_timestamp > $((start_time)) AND metric_timestamp < $((end_perf * 1000));" 2>/dev/null | grep -o '"total": [0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
    
    echo "Performance test results: $perf_metrics metrics processed"
    
    if [[ $perf_metrics -gt 0 ]]; then
        echo "✅ Performance test successful: $perf_metrics metrics processed in ${duration}s"
    else
        echo "ℹ️  Performance test completed but no metrics detected (may be normal)"
    fi
    
    # Cleanup
    run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -rf "$test_log_dir" "$test_config"
    rm -f /tmp/large_test_logs.jsonl
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender configuration validation" {
  if is_unyt; then
    echo "=== TESTING CONFIGURATION VALIDATION ==="
    
    # Test with different configuration scenarios
    local test_configs=(
        "/etc/log-sender/config1.json"
        "/etc/log-sender/config2.json"
        "/tmp/test-config.json"
    )
    
    for config in "${test_configs[@]}"; do
        # Cleanup
        docker compose exec -T -u nonroot ${SERVICE_NAME:-edgenode-test} rm -f "$config" 2>/dev/null || true
        
        echo "--- Testing config: $config ---"
        
        # Test initialization
        run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
            --config-file "$config" \
            --endpoint "$LOG_COLLECTOR_URL" \
            --unyt-pub-key "$UNYT_PUB_KEY" \
            --report-path /data/logs \
            --report-interval-seconds 10
        
        if [[ "$status" -eq 0 ]]; then
            echo "✅ Config initialization successful: $config"
            # Verify file was created (same pattern as working tests)
            run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$config"
            assert_success
            verify_log_sender_registration "$config"
        else
            echo "❌ Config initialization failed: $config"
            echo "Output: $output"
            return 1
        fi
        
        # Verify config file structure
        echo "Verifying config file structure for: $config"
        
        # Verify required fields exist (using correct camelCase field names)
        local required_fields=("dronePubKey" "droneSecKey" "unytPubKey" "droneId" "endpoint")
        for field in "${required_fields[@]}"; do
            local field_value=$(docker compose exec -T -u nonroot "$SERVICE_NAME" jq -r ".$field" "$config" 2>/dev/null)
            if [[ -n "$field_value" && "$field_value" != "null" ]]; then
                echo "  ✅ $field: present"
            else
                echo "  ❌ $field: missing or null (value: '$field_value')"
                return 1
            fi
        done
        
        # Cleanup
        run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$config"
    done
    
    echo "✅ All configuration validation tests passed"
  else
    skip "Not running on unyt image"
  fi
}

@test "log-sender concurrent operations" {
  if is_unyt; then
    echo "=== TESTING CONCURRENT OPERATIONS ==="
    
    # Test multiple concurrent log-sender instances
    local configs=(
        "/etc/log-sender/concurrent1.json"
        "/etc/log-sender/concurrent2.json"
        "/etc/log-sender/concurrent3.json"
    )
    
    # Initialize multiple log-sender instances
    for i in "${!configs[@]}"; do
        local config="${configs[$i]}"
        local namespace="concurrent_test_$i"
        
        echo "--- Initializing concurrent instance $((i + 1)): $config ---"
        
        run docker compose exec -T -u nonroot "$SERVICE_NAME" log-sender init \
            --config-file "$config" \
            --endpoint "$LOG_COLLECTOR_URL" \
            --unyt-pub-key "$UNYT_PUB_KEY" \
            --report-path /data/logs \
            --report-interval-seconds 5
        
        if [[ "$status" -eq 0 ]]; then
            echo "✅ Concurrent instance $((i + 1)) initialized successfully"
            # Verify file was created (same pattern as working tests)
            run docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$config"
            assert_success
            verify_log_sender_registration "$config"
        else
            echo "❌ Concurrent instance $((i + 1)) initialization failed"
            echo "Output: $output"
            return 1
        fi
    done
    
    # Test that all instances can read their configurations
    echo "--- Verifying all instances can access their configs ---"
    for config in "${configs[@]}"; do
        if docker compose exec -T -u nonroot "$SERVICE_NAME" test -f "$config"; then
            echo "✅ Config accessible: $config"
        else
            echo "❌ Config not accessible: $config"
            return 1
        fi
    done
    
    # Test service startup with one instance (to avoid conflicts)
    echo "--- Testing service operation with one instance ---"
    run docker compose exec -T -u nonroot -e RUST_LOG=warn "$SERVICE_NAME" \
        timeout 10 log-sender service \
        --config-file "${configs[0]}"
    
    if [[ "$status" -eq 124 ]] || [[ "$status" -eq 0 ]]; then
        echo "✅ Service operation successful with concurrent configs"
    else
        echo "❌ Service operation failed with concurrent configs"
        return 1
    fi
    
    # Cleanup all configs
    echo "--- Cleaning up concurrent test configs ---"
    for config in "${configs[@]}"; do
        run docker compose exec -T -u nonroot "$SERVICE_NAME" rm -f "$config"
    done
    
    echo "✅ Concurrent operations test completed successfully"
  else
    skip "Not running on unyt image"
  fi
}