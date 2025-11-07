#!/bin/bash

# Database Delta Tracking Script for UNYT Tests
# This script tracks database changes during test execution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILES="-f docker-compose.base.yml -f docker-compose.unyt.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to query database count
query_db_count() {
    local table="$1"
    local description="${2:-$table}"
    local display="${3:-true}"
    
    if [[ "$display" == "true" ]]; then
        echo "--- Querying $description ---"
    fi
    
    # Try multiple parsing approaches for robustness
    local count="0"
    local raw_output=$(docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
        --command="SELECT COUNT(*) as total FROM $table;" 2>/dev/null)
    
    # Try parsing with jq if available
    if command -v jq &> /dev/null; then
        count=$(echo "$raw_output" | jq -r '.[0].total // 0' 2>/dev/null || echo "0")
    else
        # Fallback to grep parsing but more flexible
        count=$(echo "$raw_output" | grep -E '"total"|total' | grep -oE '[0-9]+' | head -1 || echo "0")
    fi
    
    # Validate count is a number
    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        count="0"
    fi
    
    if [[ "$display" == "true" ]]; then
        echo "  $table count: $count"
    fi
    echo "$count"
}

# Function to get detailed table contents
get_table_sample() {
    local table="$1"
    local limit="${2:-5}"
    local order="${3:-DESC}"
    
    case "$table" in
        "metrics")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, signing_pub_key, metric_value, metric_timestamp, verified FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"signing_pub_key":|"metric_value":|"metric_timestamp":|"verified":' | head -20 || echo "No data"
            ;;
        "drone_registrations")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, drone_pub_key, unyt_pub_key, status, registered_at FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"drone_pub_key":|"unyt_pub_key":|"status":|"registered_at":' | head -20 || echo "No data"
            ;;
        "dna_registrations")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, drone_pub_key, dna_hash, agreement_id, status FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"drone_pub_key":|"dna_hash":|"agreement_id":|"status":' | head -20 || echo "No data"
            ;;
        "invoice_periods")
            docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
                --command="SELECT id, period_start, period_end, metrics_count, drones_count, invoice_reference FROM $table ORDER BY id $order LIMIT $limit;" 2>/dev/null | \
                grep -E '"id":|"period_start":|"period_end":|"metrics_count":|"drones_count":|"invoice_reference":' | head -20 || echo "No data"
            ;;
        *)
            echo "Unknown table: $table"
            ;;
    esac
}

# Function to create baseline snapshot
create_baseline() {
    echo -e "${BLUE}=== CREATING DATABASE BASELINE ===${NC}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Create directory for baseline
    local baseline_dir=$(mktemp -d /tmp/db_baseline_XXXXXX)
    
    # Query all tables
    for table in metrics drone_registrations dna_registrations invoice_periods; do
        echo "--- BASELINE: $table ---"
        query_db_count "$table" "$table (baseline)" "false" > "$baseline_dir/${table}_baseline.txt"
    done
    
    # Get samples of recent data
    echo ""
    echo "--- BASELINE: Recent Metrics Sample ---"
    get_table_sample "metrics" 3 "DESC" > "$baseline_dir/metrics_sample.txt"
    
    echo "--- BASELINE: Recent Drone Registrations Sample ---"
    get_table_sample "drone_registrations" 3 "DESC" > "$baseline_dir/drone_regs_sample.txt"
    
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
    local current_metrics=$(query_db_count "metrics" "metrics (current)" "false")
    local current_drone_regs=$(query_db_count "drone_registrations" "drone_registrations (current)" "false")
    local current_dna_regs=$(query_db_count "dna_registrations" "dna_registrations (current)" "false")
    local current_invoice_periods=$(query_db_count "invoice_periods" "invoice_periods (current)" "false")
    
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
    
    # Display results
    echo ""
    echo -e "${BLUE}=== DELTA SUMMARY ===${NC}"
    printf "%-20s %10s → %10s  %+8s\n" "Table" "Baseline" "Current" "Delta"
    echo "--------------------------------------------------------"
    printf "%-20s %10s → %10s  %+8s\n" "metrics" "$baseline_metrics" "$current_metrics" "$delta_metrics"
    printf "%-20s %10s → %10s  %+8s\n" "drone_registrations" "$baseline_drone_regs" "$current_drone_regs" "$delta_drone_regs"
    printf "%-20s %10s → %10s  %+8s\n" "dna_registrations" "$baseline_dna_regs" "$current_dna_regs" "$delta_dna_regs"
    printf "%-20s %10s → %10s  %+8s\n" "invoice_periods" "$baseline_invoice_periods" "$current_invoice_periods" "$delta_invoice_periods"
    
    # Show recent data added
    echo ""
    echo -e "${GREEN}=== NEW DATA SAMPLE (Most Recent) ===${NC}"
    
    echo "--- Recent Metrics (Last 3) ---"
    get_table_sample "metrics" 3 "DESC"
    
    echo ""
    echo "--- Recent Drone Registrations (Last 3) ---"
    get_table_sample "drone_registrations" 3 "DESC"
    
    # Save results
    local results_file="/tmp/db_delta_results_$(date +%s).txt"
    {
        echo "Database Delta Analysis Results"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "Delta Summary:"
        echo "  metrics: $baseline_metrics → $current_metrics (Δ$delta_metrics)"
        echo "  drone_registrations: $baseline_drone_regs → $current_drone_regs (Δ$delta_drone_regs)"
        echo "  dna_registrations: $baseline_dna_regs → $current_dna_regs (Δ$delta_dna_regs)"
        echo "  invoice_periods: $baseline_invoice_periods → $current_invoice_periods (Δ$delta_invoice_periods)"
    } > "$results_file"
    
    echo ""
    echo -e "${GREEN}✅ Delta analysis complete. Results saved to: $results_file${NC}"
    
    # Display summary
    echo ""
    echo -e "${BLUE}=== TEST IMPACT SUMMARY ===${NC}"
    if [[ $delta_metrics -gt 0 ]]; then
        echo -e "${GREEN}✅ Metrics added: $delta_metrics${NC}"
    else
        echo -e "${YELLOW}ℹ️  No new metrics${NC}"
    fi
    
    if [[ $delta_drone_regs -gt 0 ]]; then
        echo -e "${GREEN}✅ Drone registrations added: $delta_drone_regs${NC}"
    else
        echo -e "${YELLOW}ℹ️  No new drone registrations${NC}"
    fi
    
    if [[ $delta_dna_regs -gt 0 ]]; then
        echo -e "${GREEN}✅ DNA registrations added: $delta_dna_regs${NC}"
    else
        echo -e "${YELLOW}ℹ️  No new DNA registrations${NC}"
    fi
    
    if [[ $delta_invoice_periods -gt 0 ]]; then
        echo -e "${GREEN}✅ Invoice periods added: $delta_invoice_periods${NC}"
    else
        echo -e "${YELLOW}ℹ️  No new invoice periods${NC}"
    fi
    
    # Clean up baseline if requested
    if [[ "${CLEANUP_BASELINE:-false}" == "true" ]]; then
        rm -rf "$baseline_dir"
        echo ""
        echo -e "${YELLOW}🧹 Cleaned up baseline directory${NC}"
    fi
}

# Function to monitor database during test execution
monitor_during_tests() {
    echo -e "${BLUE}=== MONITORING DATABASE DURING TEST EXECUTION ===${NC}"
    
    # Create baseline
    local baseline_dir=$(create_baseline)
    
    echo ""
    echo -e "${YELLOW}⚠️  Baseline created. Now run your tests...${NC}"
    echo "When tests are complete, run this script again with the baseline directory:"
    echo "  compare_with_baseline \"$baseline_dir\""
    echo ""
    echo "Or run with TEST_MODE=compare to automatically compare:"
    echo "  compare_with_baseline \"$baseline_dir\""
    
    # If TEST_MODE is set to compare, automatically compare after a delay
    if [[ "${TEST_MODE:-}" == "compare" ]]; then
        echo ""
        echo -e "${BLUE}⏳ Waiting 60 seconds for tests to complete...${NC}"
        sleep 60
        compare_with_baseline "$baseline_dir"
    fi
}

# Main execution
case "${1:-help}" in
    "baseline")
        create_baseline
        ;;
    "compare")
        if [[ -z "$2" ]]; then
            echo "Error: Baseline directory required for comparison"
            echo "Usage: $0 compare <baseline_directory>"
            exit 1
        fi
        compare_with_baseline "$2"
        ;;
    "monitor")
        monitor_during_tests
        ;;
    "help"|*)
        echo "Database Delta Tracking Script"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  baseline      - Create database baseline snapshot"
        echo "  compare <dir> - Compare current state with baseline directory"
        echo "  monitor       - Interactive monitoring (create baseline, wait, compare)"
        echo "  help          - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  TEST_MODE=compare - Automatically compare after creating baseline"
        echo "  CLEANUP_BASELINE=true - Remove baseline after comparison"
        echo ""
        echo "Examples:"
        echo "  # Create baseline and manually compare later"
        echo "  $0 baseline"
        echo ""
        echo "  # Monitor during test execution"
        echo "  TEST_MODE=compare $0 monitor"
        echo ""
        echo "  # Compare with existing baseline"
        echo "  $0 compare /tmp/db_baseline_1234567890"
        ;;
esac