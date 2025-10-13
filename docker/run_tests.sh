#!/bin/bash

set -e

IMAGE_NAME=${1:-"local-edgenode"}
CONTAINER_NAME="edgenode-test"
TEST_DATA_DIR="holo-data-test"

cleanup() {
  echo "Cleaning up..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -rf "$TEST_DATA_DIR" || true
}

trap cleanup EXIT

# Initialize git submodules for bats
git submodule update --init --recursive

# Build image if it's a local build
if [[ "$IMAGE_NAME" == "local-edgenode" ]]; then
  docker build -t local-edgenode . -f Dockerfile
fi

# Run container
mkdir -p "$TEST_DATA_DIR"
docker run -d --name "$CONTAINER_NAME" -v "$(pwd)/$TEST_DATA_DIR:/data" "$IMAGE_NAME"

# Wait for startup
sleep 5

# Run tests
./tests/libs/bats/bin/bats tests