#!/bin/bash

set -ex

IMAGE_NAME=${1:-"local-edgenode"}
CONTAINER_NAME="edgenode-test"
TEST_DATA_DIR="holo-data-test"

# Determine the script's directory and the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to the docker directory
cd "$SCRIPT_DIR"

cleanup() {
  echo "Cleaning up..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  sudo rm -rf "$TEST_DATA_DIR" || true
}

trap cleanup EXIT

# Build image if it's a local build
if [[ "$IMAGE_NAME" == "local-edgenode" ]]; then
  docker build -t local-edgenode . -f Dockerfile
elif [[ "$IMAGE_NAME" == "local-edgenode-go-pion" ]]; then
  docker build -t local-edgenode-go-pion . -f Dockerfile.go-pion
fi

# Run container
mkdir -p "$TEST_DATA_DIR"
docker run -d --name "$CONTAINER_NAME" -v "$(pwd)/$TEST_DATA_DIR:/data" "$IMAGE_NAME"

# Wait for startup
sleep 5

# Run tests using relative path from docker directory
IMAGE_NAME=$IMAGE_NAME ./tests/libs/bats/bin/bats tests