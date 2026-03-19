#!/bin/bash

set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="${1:-local-edgenode-harvester}"
SERVICE_NAME="edgenode-harvester"
CLEANUP="${CLEANUP:-true}"

echo "Testing harvester image: $IMAGE_NAME"

cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        echo "Cleaning up..."
        docker compose down -v --remove-orphans
    fi
}
trap cleanup EXIT

# Build local image unless running in CI release test mode
if [[ "$CI_RELEASE_TEST" != "true" ]] && [[ "$IMAGE_NAME" == local-edgenode-harvester* ]]; then
    echo "Building local harvester image: $IMAGE_NAME"
    docker build \
        --secret id=github_token,env=GITHUB_TOKEN \
        -t "$IMAGE_NAME" \
        -f Dockerfile.harvester \
        .
fi

export HARVESTER_IMAGE="$IMAGE_NAME"
export IMAGE_NAME
export SERVICE_NAME
export SCRIPT_DIR
export COMPOSE_PROJECT_NAME="edgenode"

# Start services
echo "Starting services..."
docker compose up --build -d log-collector "$SERVICE_NAME"

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

# Harvester has a longer startup — conductor init + happ install
echo "Waiting for harvester to start (up to 120s)..."
MAX_WAIT=120
WAIT_TIME=0
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker compose exec -T "$SERVICE_NAME" test -f /data/logs/startup.log 2>/dev/null && \
       docker compose exec -T "$SERVICE_NAME" grep -q "Starting log-harvester service" /data/logs/startup.log 2>/dev/null; then
        echo "Harvester is ready"
        break
    fi
    echo "Waiting for harvester... ($WAIT_TIME/$MAX_WAIT seconds)"
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

# Resolve actual container name
ACTUAL_CONTAINER=$(docker compose ps -q "$SERVICE_NAME" 2>/dev/null | head -n 1)
if [ -n "$ACTUAL_CONTAINER" ]; then
    export CONTAINER_NAME="$ACTUAL_CONTAINER"
    echo "Found container: $CONTAINER_NAME for service: $SERVICE_NAME"
else
    export CONTAINER_NAME="edgenode-${SERVICE_NAME}-1"
    echo "Warning: container not found, using fallback: $CONTAINER_NAME"
fi

# Run harvester-specific tests only
echo "Running harvester tests..."
set +e
./tests/libs/bats/bin/bats tests/harvester_startup.bats tests/harvester_process.bats
TEST_EXIT_CODE=$?
set -e

if [ $TEST_EXIT_CODE -ne 0 ]; then
    echo "Tests failed. Printing container logs..."
    docker compose logs "$SERVICE_NAME"
    echo "--- startup.log ---"
    docker compose exec -T "$SERVICE_NAME" cat /data/logs/startup.log 2>/dev/null || true
fi

echo "Harvester test execution completed with exit code: $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE
