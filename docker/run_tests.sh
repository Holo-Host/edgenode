#!/bin/bash

set -ex

IMAGE_NAME=${1}

if [ -z "$IMAGE_NAME" ]; then
  echo "Usage: $0 <image-name>"
  echo "e.g. for a local build: $0 local-edgenode-unyt"
  echo "e.g. for a remote image: $0 ghcr.io/holo-host/edgenode:v0.1.0-hc-0.5.6"
  exit 1
fi

# Determine the script's directory and the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to the docker directory
cd "$SCRIPT_DIR"

cleanup() {
  echo "Cleaning up..."
  docker compose down -v --remove-orphans
}

trap cleanup EXIT

# Export variables for docker compose and bats
export EDGENODE_IMAGE="${IMAGE_NAME}"
export IMAGE_NAME
export SCRIPT_DIR

# Start services
docker compose up --build -d

# Wait for startup
sleep 10

# Run tests from the host
set +e # Disable exit on error
./tests/libs/bats/bin/bats tests
test_exit_code=$?
set -e # Re-enable exit on error

# Print logs on failure
if [ $test_exit_code -ne 0 ]; then
  echo "Tests failed. Printing container logs..."
  docker compose logs
fi

exit $test_exit_code