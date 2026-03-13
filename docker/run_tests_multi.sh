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

# Start services (--build needed for log-collector)
echo "Starting services..."
docker compose up --build -d

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

# Run tests
echo "Running tests..."
set +e
./tests/libs/bats/bin/bats tests
TEST_EXIT_CODE=$?
set -e

if [ $TEST_EXIT_CODE -ne 0 ]; then
    echo "Tests failed. Printing container logs..."
    docker compose logs
fi

echo "Test execution completed with exit code: $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE
