#!/bin/bash

# Simple test for database delta tracking

COMPOSE_FILES="-f docker-compose.base.yml -f docker-compose.unyt.yml"

# Test basic query
echo "Testing basic database query..."

# Get current counts
echo "Querying metrics table..."
metrics_count=$(docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT COUNT(*) as total FROM metrics;" 2>/dev/null | \
    grep -o '"total": [0-9]*' | \
    grep -o '[0-9]*' | \
    head -1 || echo "0")

echo "Metrics count: $metrics_count"

echo "Querying drone_registrations table..."
drone_count=$(docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT COUNT(*) as total FROM drone_registrations;" 2>/dev/null | \
    grep -o '"total": [0-9]*' | \
    grep -o '[0-9]*' | \
    head -1 || echo "0")

echo "Drone registrations count: $drone_count"

echo "Querying dna_registrations table..."
dna_count=$(docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT COUNT(*) as total FROM dna_registrations;" 2>/dev/null | \
    grep -o '"total": [0-9]*' | \
    grep -o '[0-9]*' | \
    head -1 || echo "0")

echo "DNA registrations count: $dna_count"

echo "Querying invoice_periods table..."
invoice_count=$(docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT COUNT(*) as total FROM invoice_periods;" 2>/dev/null | \
    grep -o '"total": [0-9]*' | \
    grep -o '[0-9]*' | \
    head -1 || echo "0")

echo "Invoice periods count: $invoice_count"

echo ""
echo "=== CURRENT DATABASE STATE ==="
printf "%-20s %10s\n" "Table" "Count"
printf "%-20s %10s\n" "metrics" "$metrics_count"
printf "%-20s %10s\n" "drone_registrations" "$drone_count"
printf "%-20s %10s\n" "dna_registrations" "$dna_count"
printf "%-20s %10s\n" "invoice_periods" "$invoice_count"

# Get recent data samples
echo ""
echo "=== RECENT DATA SAMPLES ==="
echo "Recent metrics:"
docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT id, signing_pub_key, metric_value, metric_timestamp, verified FROM metrics ORDER BY id DESC LIMIT 3;" 2>/dev/null | \
    grep -E '"id":|"signing_pub_key":|"metric_value":|"metric_timestamp":|"verified":' | head -15 || echo "No data"

echo ""
echo "Recent drone registrations:"
docker compose $COMPOSE_FILES exec -T log-collector npx --yes wrangler d1 execute log-collector-db \
    --command="SELECT id, drone_pub_key, unyt_pub_key, status, registered_at FROM drone_registrations ORDER BY id DESC LIMIT 3;" 2>/dev/null | \
    grep -E '"id":|"drone_pub_key":|"unyt_pub_key":|"status":|"registered_at":' | head -15 || echo "No data"