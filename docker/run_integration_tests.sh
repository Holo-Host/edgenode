#!/bin/bash

# Integration Data Pipeline Test Runner
# This script runs the integration tests that actually populate the database

set -ex

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments (default to UNYT image for integration tests)
IMAGE_NAME="${1:-local-edgenode-unyt}"
COMPOSE_FILES="-f $SCRIPT_DIR/docker-compose.base.yml"
DOCKERFILE_SUFFIX=""
CLEANUP="${CLEANUP:-true}"

# Determine compose file and service name based on image
# Note: Integration tests only support UNYT image
case "$IMAGE_NAME" in
    *unyt*)
        COMPOSE_FILES="$COMPOSE_FILES -f $SCRIPT_DIR/docker-compose.unyt.yml"
        DOCKERFILE_SUFFIX="unyt"
        SERVICE_NAME="edgenode-unyt"
        ;;
    *)
        echo "Unknown image: $IMAGE_NAME"
        echo "This integration test runner only supports UNYT images:"
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

# Export environment variables
export EDGENODE_IMAGE="$IMAGE_NAME"
export IMAGE_NAME
export SCRIPT_DIR
export COMPOSE_FILES
export COMPOSE_PROJECT_NAME="edgenode"
export SERVICE_NAME="$SERVICE_NAME"
export UNYT_PUB_KEY="uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"
export UNYT_PUB_KEY="uhCAkjC1PlxEz1LTEPytaNL10L9oy2kixwAABEjRWeKvN7xIAAAAB"

# For UNYT images, ensure we use the locally built base image
if [[ "$IMAGE_NAME" == *unyt* ]]; then
    export EDGENODE_HC_0_6_0_IMAGE="local-edgenode-hc-0.6.0-dev-go-pion"
    echo "Using local base image: $EDGENODE_HC_0_6_0_IMAGE"
fi

# Ensure a clean slate before starting
echo "Ensuring a clean slate by running docker compose down..."
docker compose $COMPOSE_FILES down -v --remove-orphans || true
# Also remove any dangling containers that might cause conflicts
docker ps -aq --filter "name=edgenode" | xargs -r docker rm -f

# Check if services are already running and clean up if needed
echo "Checking for existing services..."

# Also check for any containers using port 8787 and stop them
PORT_8787_CONTAINER_ID=$(docker ps -q --filter "publish=8787" 2>/dev/null)
if [ -n "$PORT_8787_CONTAINER_ID" ]; then
    echo "Found container(s) using port 8787: $PORT_8787_CONTAINER_ID"
    echo "Stopping and removing them..."
    docker stop $PORT_8787_CONTAINER_ID 2>/dev/null || true
    docker rm $PORT_8787_CONTAINER_ID 2>/dev/null || true
fi

# Force cleanup any existing containers that might be using the same ports
echo "Force cleaning up any existing containers..."
docker ps --filter "name=edgenode" --format "{{.Names}}" | while read container; do
    if [ -n "$container" ]; then
        echo "Stopping existing container: $container"
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    fi
done

EXISTING_CONTAINERS=$(docker compose $COMPOSE_FILES ps --services 2>/dev/null | head -1)
if [ -n "$EXISTING_CONTAINERS" ]; then
    echo "Found existing services, cleaning up first..."
    docker compose $COMPOSE_FILES down -v --remove-orphans
    sleep 3
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
MAX_WAIT=60
WAIT_TIME=0
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker compose $COMPOSE_FILES ps edgenode-unyt | grep -q "healthy"; then
        echo "Edgenode service is healthy"
        break
    fi
    echo "Waiting for edgenode service to be healthy... ($WAIT_TIME/$MAX_WAIT seconds)"
    sleep 5
    WAIT_TIME=$((WAIT_TIME + 5))
done

# Set the actual container name for docker cp operations that don't work with docker compose cp
# Wait a moment for containers to be created
sleep 2
ACTUAL_CONTAINER=$(docker compose $COMPOSE_FILES ps -q "$SERVICE_NAME" 2>/dev/null | head -n 1)
if [ -n "$ACTUAL_CONTAINER" ]; then
    export CONTAINER_NAME="$ACTUAL_CONTAINER"
    echo "Found container: $CONTAINER_NAME for service: $SERVICE_NAME"
else
    echo "Warning: Could not find container for service $SERVICE_NAME"
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    # Fallback: use project prefix + service name + instance number
    export CONTAINER_NAME="docker-${SERVICE_NAME}-1"
    echo "Using fallback container name: $CONTAINER_NAME"
fi

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
BASELINE_DIR=$(./track_database_delta.sh baseline | tail -n 1)
echo "Baseline created in: $BASELINE_DIR"

echo ""
echo "=========================================="
echo "STARTING INTEGRATION TESTS"
echo "=========================================="
echo ""

# Run the integration tests
sleep 10
set +e # Disable exit on error
./tests/libs/bats/bin/bats tests/log_sender_debug.bats
./tests/libs/bats/bin/bats tests/integration_data_pipeline.bats
TEST_EXIT_CODE=$?
set -e # Re-enable exit on error

# Print logs on failure
if [ $TEST_EXIT_CODE -ne 0 ]; then
    echo "Tests failed. Printing container logs..."
    docker compose $COMPOSE_FILES logs
    echo "Service status:"
    docker compose $COMPOSE_FILES ps
fi

echo ""
echo "=========================================="
echo "INTEGRATION TESTS COMPLETED"
echo "=========================================="
echo ""

# Create database delta after tests
echo "=== CREATING DATABASE DELTA ==="
./track_database_delta.sh compare "$BASELINE_DIR"

echo ""
echo "=== INTEGRATION TEST SUMMARY ==="
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✅ ALL INTEGRATION TESTS PASSED!"
    echo ""
    echo "The integration tests above successfully:"
    echo "  ✅ Populated the database with test metrics"
    echo "  ✅ Stored drone registrations"
    echo "  ✅ Verified data persistence across multiple runs"
    echo "  ✅ Tested real-time data processing"
    echo "  ✅ Validated data integrity with edge cases"
    echo "  ✅ Demonstrated complete cleanup and reset"
else
    echo "❌ SOME INTEGRATION TESTS FAILED (exit code: $TEST_EXIT_CODE)"
fi

echo ""
echo "Check the delta results above to see the actual database impact!"
echo ""

exit $TEST_EXIT_CODE