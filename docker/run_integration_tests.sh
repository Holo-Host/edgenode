#!/bin/bash

# Integration Data Pipeline Test Runner
# This script runs the integration tests that actually populate the database

set -ex

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
IMAGE_NAME="${1:-local-edgenode-unyt}"
COMPOSE_FILES="-f docker-compose.base.yml"
DOCKERFILE_SUFFIX=""
CLEANUP="${CLEANUP:-true}"

# Determine compose file and service name based on image
case "$IMAGE_NAME" in
    *unyt*)
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.unyt.yml"
        DOCKERFILE_SUFFIX="unyt"
        SERVICE_NAME="edgenode-unyt"
        ;;
    *)
        echo "Unknown image: $IMAGE_NAME"
        echo "Supported images:"
        echo "  - local-edgenode-unyt"
        exit 1
        ;;
esac

echo "=========================================="
echo "INTEGRATION DATA PIPELINE TEST RUNNER"
echo "=========================================="
echo ""
echo "Testing image: $IMAGE_NAME"
echo "Service name: $SERVICE_NAME"
echo "Compose files: $COMPOSE_FILES"
echo ""
echo "This runner executes integration tests that:"
echo "  ✅ Actually populate the local database with test data"
echo "  ✅ Test the real data pipeline from log-sender to database"
echo "  ✅ Verify data integrity and persistence"
echo "  ✅ Clean up test data between runs"
echo ""

# Cleanup function
cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        echo "Cleaning up..."
        docker compose $COMPOSE_FILES down -v --remove-orphans
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Build local images if needed
if [[ "$IMAGE_NAME" == local-edgenode-* ]] && [[ "$IMAGE_NAME" != *unyt* ]]; then
    echo "Building local image: $IMAGE_NAME"
    DOCKERFILE_NAME="Dockerfile.$(echo "$IMAGE_NAME" | sed 's/^local-edgenode-//')"
    "$SCRIPT_DIR/build-images.sh" "$DOCKERFILE_NAME"
fi

# Export environment variables
export EDGENODE_IMAGE="$IMAGE_NAME"
export IMAGE_NAME
export SCRIPT_DIR
export COMPOSE_FILES
export COMPOSE_PROJECT_NAME="edgenode"

# For UNYT images, ensure we use the locally built base image
if [[ "$IMAGE_NAME" == *unyt* ]]; then
    export EDGENODE_HC_0_6_0_IMAGE="local-edgenode-hc-0.6.0-dev-go-pion"
    echo "Using local base image: $EDGENODE_HC_0_6_0_IMAGE"
fi

# Wait for containers to be created
sleep 5

# Export service name for tests
export SERVICE_NAME="$SERVICE_NAME"

# Set the actual container name for docker cp operations that don't work with docker compose cp
sleep 2
ACTUAL_CONTAINER=$(docker compose $COMPOSE_FILES ps -q "$SERVICE_NAME" 2>/dev/null | head -n 1)
if [ -n "$ACTUAL_CONTAINER" ]; then
    export CONTAINER_NAME="$ACTUAL_CONTAINER"
    echo "Found container: $CONTAINER_NAME for service: $SERVICE_NAME"
else
    echo "Warning: Could not find container for service $SERVICE_NAME"
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    export CONTAINER_NAME="docker-${SERVICE_NAME}-1"
    echo "Using fallback container name: $CONTAINER_NAME"
fi

# Start services
echo "Starting services..."
if [[ "$IMAGE_NAME" == *unyt* ]]; then
    echo "UNYT image detected - using --build for log-collector and UNYT image"
    docker compose $COMPOSE_FILES up --build -d
else
    echo "HC image detected - using pre-built images"
    docker compose $COMPOSE_FILES up -d
fi

# Wait for services to be healthy
echo "Waiting for services to be ready..."
sleep 10

# Only wait for log-collector if it's included in the compose files
if echo "$COMPOSE_FILES" | grep -q "unyt"; then
    echo "UNYT image detected, waiting for log-collector..."
    MAX_WAIT=60
    WAIT_TIME=0
    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        if docker compose $COMPOSE_FILES ps log-collector | grep -q "healthy"; then
            echo "Log-collector is healthy"
            break
        fi
        echo "Waiting for log-collector to be healthy... ($WAIT_TIME/$MAX_WAIT seconds)"
        sleep 5
        WAIT_TIME=$((WAIT_TIME + 5))
    done
else
    echo "Non-UNYT image detected, skipping log-collector wait..."
fi

# Wait for edgenode service to start
echo "Waiting for edgenode service to start..."
sleep 15

# Check if the integration test file exists
if [[ ! -f "$SCRIPT_DIR/tests/integration_data_pipeline.bats" ]]; then
    echo "❌ Error: integration_data_pipeline.bats not found"
    exit 1
fi

echo "✅ Integration test file found"
echo ""

# Create database baseline before tests
echo "=== CREATING DATABASE BASELINE ==="
cd "$SCRIPT_DIR"
./track_database_delta.sh baseline

echo ""
echo "=========================================="
echo "STARTING INTEGRATION TESTS"
echo "=========================================="
echo ""

# Run the integration tests
set +e # Disable exit on error
./tests/libs/bats/bin/bats tests/integration_data_pipeline.bats
TEST_EXIT_CODE=$?
set -e # Re-enable exit on error

echo ""
echo "=========================================="
echo "INTEGRATION TESTS COMPLETED"
echo "=========================================="
echo ""

# Create database delta after tests
echo "=== CREATING DATABASE DELTA ==="
./track_database_delta.sh delta

echo ""
echo "=== INTEGRATION TEST SUMMARY ==="
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✅ ALL INTEGRATION TESTS PASSED!"
    echo ""
    echo "The integration tests above successfully:"
    echo "  ✅ Populated the database with test metrics"
{ _ble_edit_exec_gexec__save_lastarg "$@"; } 4>&1 5>&2 &>/dev/null
