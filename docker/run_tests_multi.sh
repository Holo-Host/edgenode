#!/bin/bash

# Multi-Image Test Runner Script
# Supports testing multiple Docker images with proper dependency management

set -ex

# Script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to docker directory
cd "$SCRIPT_DIR"

# Parse command line arguments
IMAGE_NAME="${1:-local-edgenode-hc-0.5.6}"
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
    *hc-0.6.0-dev-go-pion*|*go-pion*)
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.hc-0.6.0-dev-go-pion.yml"
        DOCKERFILE_SUFFIX="hc-0.6.0-dev-go-pion"
        SERVICE_NAME="edgenode-hc-0.6.0-dev-go-pion"
        ;;
    *hc-0.5.6*)
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.hc-0.5.6.yml"
        DOCKERFILE_SUFFIX="hc-0.5.6"
        SERVICE_NAME="edgenode-hc-0.5.6"
        # Note: Docker Compose creates container names with project prefix
        # The actual container name will be "docker-edgenode-hc-0.5.6-1"
        ;;
    *)
        echo "Unknown image: $IMAGE_NAME"
        echo "Supported images:"
        echo "  - local-edgenode-hc-0.5.6"
        echo "  - local-edgenode-hc-0.6.0-dev-go-pion"
        echo "  - local-edgenode-unyt"
        exit 1
        ;;
esac

echo "Testing image: $IMAGE_NAME"
echo "Service name: $SERVICE_NAME"
echo "Compose files: $COMPOSE_FILES"

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
# Note: For UNYT images, we skip the initial build here because docker compose up --build
# will build it with the correct base image context. Building twice causes the second build
# to overwrite the first with potentially different layers.
if [[ "$IMAGE_NAME" == local-edgenode-* ]] && [[ "$IMAGE_NAME" != *unyt* ]]; then
    echo "Building local image: $IMAGE_NAME"
    DOCKERFILE_NAME="Dockerfile.$(echo "$IMAGE_NAME" | sed 's/^local-edgenode-//')"
    ./build-images.sh "$DOCKERFILE_NAME"
fi

# Export environment variables
export EDGENODE_IMAGE="$IMAGE_NAME"
export IMAGE_NAME
export SCRIPT_DIR
export COMPOSE_FILES
# Set explicit project name to ensure consistent network/volume naming
export COMPOSE_PROJECT_NAME="edgenode"

# For UNYT images, ensure we use the locally built base image
if [[ "$IMAGE_NAME" == *unyt* ]]; then
    export EDGENODE_HC_0_6_0_IMAGE="local-edgenode-hc-0.6.0-dev-go-pion"
    echo "Using local base image: $EDGENODE_HC_0_6_0_IMAGE"
fi

# Wait for containers to be created
sleep 5

# Docker Compose creates containers with project prefix + service name
# The service in compose file is "edgenode-hc-0.5.6"
# But the container becomes "docker-edgenode-hc-0.5.6-1"
# Tests expect SERVICE_NAME to be the service name, not container name
export SERVICE_NAME="$SERVICE_NAME"  # Keep as service name for BATS tests

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

# Start services
echo "Starting services..."
# Use --build for UNYT images (needs to build log-collector + unyt with base image args)
# For HC images, we pre-built them so no --build needed
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

# Run tests
echo "Running tests..."
set +e # Disable exit on error

./tests/libs/bats/bin/bats tests
TEST_EXIT_CODE=$?
set -e # Re-enable exit on error

# Print logs on failure
if [ $TEST_EXIT_CODE -ne 0 ]; then
    echo "Tests failed. Printing container logs..."
    docker compose $COMPOSE_FILES logs
    echo "Service status:"
    docker compose $COMPOSE_FILES ps
fi

echo "Test execution completed with exit code: $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE