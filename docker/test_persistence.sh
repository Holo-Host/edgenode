#!/bin/bash
set -euo pipefail

HOST_DATA_DIR="$(pwd)/test-holo-data"
CONTAINER_NAME="trailblazer-persistence-test"
TEST_FILE="/etc/holochain/test-file.txt"
TEST_STRING="persistence is working"
IMAGE_NAME="trailblazer-local"

cleanup() {
    echo "Cleaning up..."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    sudo rm -rf "$HOST_DATA_DIR"
}

trap cleanup EXIT

echo "Building the Docker image..."
docker build -t "$IMAGE_NAME" docker

echo "Creating host directory for persistent data..."
mkdir -p "$HOST_DATA_DIR"

echo "Starting container for the first time..."
docker run --name "$CONTAINER_NAME" -dit \
  -v "$HOST_DATA_DIR:/data" \
  "$IMAGE_NAME"

echo "Creating a test file inside the container..."
docker exec "$CONTAINER_NAME" sh -c "echo '$TEST_STRING' > $TEST_FILE"

echo "Stopping and removing the container..."
docker rm -f "$CONTAINER_NAME"

echo "Starting a new container with the same volume mount..."
docker run --name "$CONTAINER_NAME" -dit \
  -v "$HOST_DATA_DIR:/data" \
  "$IMAGE_NAME"

echo "Verifying the test file exists and contains the correct content..."
CONTENT=$(docker exec "$CONTAINER_NAME" cat "$TEST_FILE")

if [ "$CONTENT" = "$TEST_STRING" ]; then
    echo "Persistence test PASSED!"
else
    echo "Persistence test FAILED!"
    echo "Expected: '$TEST_STRING'"
    echo "Got: '$CONTENT'"
    exit 1
fi
