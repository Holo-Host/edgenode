#!/bin/bash

set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="${1:-local-edgenode}"
SERVICE_NAME="edgenode"
CLEANUP="${CLEANUP:-true}"

echo "Testing image: $IMAGE_NAME"

cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        echo "Cleaning up..."
        docker compose down -v --remove-orphans
    fi
}
trap cleanup EXIT

# Build local image unless running in CI release test mode
if [[ "$CI_RELEASE_TEST" != "true" ]] && [[ "$IMAGE_NAME" == local-edgenode* ]]; then
    echo "Building local image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" -f Dockerfile .
fi

export EDGENODE_IMAGE="$IMAGE_NAME"
export IMAGE_NAME
export SERVICE_NAME
export SCRIPT_DIR
export COMPOSE_PROJECT_NAME="edgenode"

# Build log-collector separately so Docker layer cache is used on subsequent runs
echo "Building log-collector..."
docker compose build log-collector

# Start only the services needed for edgenode tests (not edgenode-harvester)
echo "Starting services..."
docker compose up -d log-collector "$SERVICE_NAME"

# Wait for log-collector
echo "Waiting for log-collector to be healthy..."
MAX_WAIT=60
WAIT_TIME=0
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker compose ps log-collector | grep -q "healthy"; then
        echo "Log-collector is healthy"
        break
    fi
    echo "Waiting for log-collector... ($WAIT_TIME/$MAX_WAIT seconds)"
    sleep 5
    WAIT_TIME=$((WAIT_TIME + 5))
done

echo "Waiting for edgenode to start..."
sleep 15

# Resolve actual container name for operations that require it
ACTUAL_CONTAINER=$(docker compose ps -q "$SERVICE_NAME" 2>/dev/null | head -n 1)
if [ -n "$ACTUAL_CONTAINER" ]; then
    export CONTAINER_NAME="$ACTUAL_CONTAINER"
    echo "Found container: $CONTAINER_NAME for service: $SERVICE_NAME"
else
    export CONTAINER_NAME="edgenode-${SERVICE_NAME}-1"
    echo "Warning: container not found, using fallback: $CONTAINER_NAME"
fi

# Wait for log-collector to be healthy (with restart support)
wait_for_log_collector() {
    local max_wait="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf http://localhost:8787/ >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "Warning: log-collector not healthy after ${max_wait}s, proceeding anyway"
    return 0
}

# Run edgenode tests — exclude harvester-specific files (those run via run_harvester_tests.sh)
# Run each file separately so a wrangler crash in one file doesn't cascade to subsequent files.
echo "Running tests..."
TEST_EXIT_CODE=0
set +e
for BATS_FILE in $(find tests -maxdepth 1 -name '*.bats' ! -name 'harvester_*' | sort); do
    echo "--- Waiting for log-collector before: $BATS_FILE ---"
    wait_for_log_collector 60
    echo "--- Running: $BATS_FILE ---"
    ./tests/libs/bats/bin/bats "$BATS_FILE"
    FILE_EXIT=$?
    if [ $FILE_EXIT -ne 0 ]; then
        echo "FAILED: $BATS_FILE (exit $FILE_EXIT)"
        TEST_EXIT_CODE=$FILE_EXIT
    fi
done
set -e

if [ $TEST_EXIT_CODE -ne 0 ]; then
    echo "Tests failed. Printing container logs..."
    docker compose logs
fi

echo "Test execution completed with exit code: $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE
