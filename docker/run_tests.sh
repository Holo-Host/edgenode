#!/bin/bash

set -ex

# Determine the script's directory and the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to the docker directory
cd "$SCRIPT_DIR"

cleanup() {
  echo "Cleaning up..."
  docker-compose down -v --remove-orphans
}

trap cleanup EXIT

# Start services
docker-compose up --build -d

# Wait for startup
sleep 10

# Set image name and script dir for tests
export IMAGE_NAME=local-edgenode-unyt
export SCRIPT_DIR

# Run tests from the host
set +e # Disable exit on error
./tests/libs/bats/bin/bats tests
test_exit_code=$?
set -e # Re-enable exit on error

# Print logs on failure
if [ $test_exit_code -ne 0 ]; then
  echo "Tests failed. Printing container logs..."
  docker-compose logs
fi

exit $test_exit_code