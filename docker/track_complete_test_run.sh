#!/bin/bash

# Database Delta Tracking Script - Complete Test Run
# This script tracks database changes during a complete test execution cycle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILES="-f docker-compose.base.yml -f docker-compose.unyt.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DATABASE DELTA TRACKING FOR UNYT TESTS ===${NC}"
echo "This script will:"
echo "1. Start the UNYT test services"
echo "2. Create baseline database snapshot"
echo "3. Run the complete test suite"
echo "4. Analyze database changes"
echo ""

# Function to query database count
query_db_count() {
    local table="$1"
    local count=$(docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM $table;" 2>/dev/null | \
        grep -o '"total": [0-9]*' | \
        grep -o '[0-9]*' | \
        head -1 || echo "0")
    echo "$count"
}

# Function to get table sample
get_table_sample() {
    local table="$1"
    local limit="${2:-3}"
    local order="${3:-DESC}"
    
    case "$table" in
        "metrics")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, signing_pub_key, metric_value, metric_timestamp, verified FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"signing_pub_key":|"metric_value":|"metric_timestamp":|"verified":' | head -15
            ;;
        "drone_registrations")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, drone_pub_key, unyt_pub_key, status, registered_at FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"drone_pub_key":|"unyt_pub_key":|"status":|"registered_at":' | head -15
            ;;
        "dna_registrations")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, drone_pub_key, dna_hash, agreement_id, status FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"drone_pub_key":|"dna_hash":|"agreement_id":|"status":' | head -15
            ;;
        "invoice_periods")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, period_start, period_end, metrics_count, drones_count, invoice_reference FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"period_start":|"period_end":|"metrics_count":|"drones_count":|"invoice_reference":' | head -15
            ;;
    esac
}

# Function to create baseline snapshot
create_baseline() {
    echo -e "${BLUE}=== CREATING BASELINE DATABASE SNAPSHOT ===${NC}" >&2
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >&2
    echo "" >&2
    
    # Create directory for baseline
    local baseline_dir="/tmp/db_baseline_$(date +%s)"
    mkdir -p "$baseline_dir"
    
    # Query all tables and save counts
    local baseline_metrics=$(query_db_count "metrics")
    local baseline_drone_regs=$(query_db_count "drone_registrations")
    local baseline_dna_regs=$(query_db_count "dna_registrations")
    local baseline_invoice_periods=$(query_db_count "invoice_periods")
    
    echo "metrics: $baseline_metrics" >&2
    echo "drone_registrations: $baseline_drone_regs" >&2
    echo "dna_registrations: $baseline_dna_regs" >&2
    echo "invoice_periods: $baseline_invoice_periods" >&2
    
    # Save counts to files
    echo "$baseline_metrics" > "$baseline_dir/metrics_baseline.txt"
    echo "$baseline_drone_regs" > "$baseline_dir/drone_registrations_baseline.txt"
    echo "$baseline_dna_regs" > "$baseline_dir/dna_registrations_baseline.txt"
    echo "$baseline_invoice_periods" > "$baseline_dir/invoice_periods_baseline.txt"
    
    # Get sample data
    echo "" > "$baseline_dir/metrics_sample.txt"
    echo "--- BASELINE: Recent Metrics (Top 3) ---" >> "$baseline_dir/metrics_sample.txt"
    get_table_sample "metrics" 3 >> "$baseline_dir/metrics_sample.txt"
    
    echo "" > "$baseline_dir/drone_regs_sample.txt"
    echo "--- BASELINE: Recent Drone Registrations (Top 3) ---" >> "$baseline_dir/drone_regs_sample.txt"
    get_table_sample "drone_registrations" 3 >> "$baseline_dir/drone_regs_sample.txt"
    
    echo "$baseline_dir"
}

# Function to compare with baseline
compare_with_baseline() {
    local baseline_dir="$1"
    
    echo ""
    echo -e "${YELLOW}=== DATABASE DELTA ANALYSIS ===${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Get current counts
    local current_metrics=$(query_db_count "metrics")
    local current_drone_regs=$(query_db_count "drone_registrations")
    local current_dna_regs=$(query_db_count "dna_registrations")
    local current_invoice_periods=$(query_db_count "invoice_periods")
    
    # Get baseline counts
    local baseline_metrics=$(cat "$baseline_dir/metrics_baseline.txt" 2>/dev/null || echo "0")
    local baseline_drone_regs=$(cat "$baseline_dir/drone_registrations_baseline.txt" 2>/dev/null || echo "0")
    local baseline_dna_regs=$(cat "$baseline_dir/dna_registrations_baseline.txt" 2>/dev/null || echo "0")
    local baseline_invoice_periods=$(cat "$baseline_dir/invoice_periods_baseline.txt" 2>/dev/null || echo "0")
    
    # Calculate deltas
    local delta_metrics=$((current_metrics - baseline_metrics))
    local delta_drone_regs=$((current_drone_regs - baseline_drone_regs))
    local delta_dna_regs=$((current_dna_regs - baseline_dna_regs))
    local delta_invoice_periods=$((current_invoice_periods - baseline_invoice_periods))
    
    # Display results table
    echo ""
    echo -e "${BLUE}=== DATABASE DELTA SUMMARY ===${NC}"
    printf "%-20s %10s → %10s  %+8s\n" "Table" "Baseline" "Current" "Delta"
    echo "--------------------------------------------------------"
    printf "%-20s %10s → %10s  %+8s\n" "metrics" "$baseline_metrics" "$current_metrics" "$delta_metrics"
    printf "%-20s %10s → %10s  %+8s\n" "drone_registrations" "$baseline_drone_regs" "$current_drone_regs" "$delta_drone_regs"
    printf "%-20s %10s → %10s  %+8s\n" "dna_registrations" "$baseline_dna_regs" "$current_dna_regs" "$delta_dna_regs"
    printf "%-20s %10s → %10s  %+8s\n" "invoice_periods" "$baseline_invoice_periods" "$current_invoice_periods" "$delta_invoice_periods"
    
    # Show what was added during tests
    echo ""
    echo -e "${GREEN}=== RECENT DATA ADDED (Most Recent) ===${NC}"
    
    if [[ $delta_metrics -gt 0 ]]; then
        echo "--- Recent Metrics (New Data) ---"
        get_table_sample "metrics" 3
    fi
    
    if [[ $delta_drone_regs -gt 0 ]]; then
        echo ""
        echo "--- Recent Drone Registrations (New Data) ---"
        get_table_sample "drone_registrations" 3
    fi
    
    # Save results
    local results_file="/tmp/db_delta_results_$(date +%s).txt"
    {
        echo "UNYT Test Database Delta Analysis"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "Test Impact Summary:"
        echo "  Metrics added: $delta_metrics"
        echo "  Drone registrations added: $delta_drone_regs"
        echo "  DNA registrations added: $delta_dna_regs"
        echo "  Invoice periods added: $delta_invoice_periods"
        echo ""
        echo "Detailed Changes:"
        echo "  metrics: $baseline_metrics → $current_metrics (Δ$delta_metrics)"
        echo "  drone_registrations: $baseline_drone_regs → $current_drone_regs (Δ$delta_drone_regs)"
        echo "  dna_registrations: $baseline_dna_regs → $current_dna_regs (Δ$delta_dna_regs)"
        echo "  invoice_periods: $baseline_invoice_periods → $current_invoice_periods (Δ$delta_invoice_periods)"
    } > "$results_file"
    
    echo ""
    echo -e "${GREEN}✅ Database delta analysis complete${NC}"
    echo "Results saved to: $results_file"
    
    # Display impact summary
    echo ""
    echo -e "${BLUE}=== TEST EXECUTION IMPACT ===${NC}"
    local total_changes=$((delta_metrics + delta_drone_regs + delta_dna_regs + delta_invoice_periods))
    
    if [[ $total_changes -gt 0 ]]; then
        echo -e "${GREEN}✅ Database changes detected during test execution:${NC}"
        [[ $delta_metrics -gt 0 ]] && echo "  • Metrics: +$delta_metrics records"
        [[ $delta_drone_regs -gt 0 ]] && echo "  • Drone registrations: +$delta_drone_regs records"
        [[ $delta_dna_regs -gt 0 ]] && echo "  • DNA registrations: +$delta_dna_regs records"
        [[ $delta_invoice_periods -gt 0 ]] && echo "  • Invoice periods: +$delta_invoice_periods records"
        echo ""
        echo "Total database records added: $total_changes"
    else
        echo -e "${YELLOW}ℹ️  No database changes detected during test execution${NC}"
        echo "This indicates that the tests ran successfully but did not add"
        echo "persistent data to the database, which is expected for many tests."
    fi
    
    # Clean up baseline
    rm -rf "$baseline_dir"
    echo ""
    echo -e "${YELLOW}🧹 Cleaned up baseline directory${NC}"
}

# Start services with UNYT image
echo -e "${BLUE}=== STARTING SERVICES ===${NC}"
cd "$SCRIPT_DIR"
export EDGENODE_IMAGE=local-edgenode-unyt
export IMAGE_NAME=local-edgenode-unyt
export SERVICE_NAME=edgenode-unyt
export COMPOSE_FILES="-f docker-compose.base.yml -f docker-compose.unyt.yml"

# Start services
echo "Starting services with UNYT image..."
docker compose $COMPOSE_FILES up -d --build

# Wait for services to be healthy
echo ""
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 10

# Wait for log-collector to be healthy
local max_wait=60
local wait_time=0
while [[ $wait_time -lt $max_wait ]]; do
    if docker compose $COMPOSE_FILES ps log-collector | grep -q healthy; then
        echo "✅ Log-collector is healthy"
        break
    fi
    echo "Waiting for log-collector... ($wait_time/$max_wait)"
    sleep 2
    wait_time=$((wait_time + 2))
done

# Wait for edgenode service
sleep 15

# Create baseline
baseline_dir=$(create_baseline)
echo ""
echo -e "${GREEN}✅ Baseline created in: $baseline_dir${NC}"

# Run tests
echo ""
echo -e "${BLUE}=== RUNNING TESTS ===${NC}"
./run_tests_multi.sh local-edgenode-unyt

# Compare results
echo ""
compare_with_baseline "$baseline_dir"

echo ""
echo -e "${GREEN}🎉 Database delta tracking completed successfully!${NC}"