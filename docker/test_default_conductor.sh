#!/bin/bash

set -e

# Idempotent cleanup
if docker ps -a --format '{{.Names}}' | grep -q '^test-default$'; then
  docker rm -f test-default
fi
rm -rf holo-data

# Build image
cd docker
docker build -t local-trailblazer . -f Dockerfile
cd ..

# Run container without CONDUCTOR_MODE
mkdir -p holo-data
docker run -d --name test-default -v "$(pwd)/holo-data:/data" local-trailblazer

# Wait for startup
sleep 5

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q '^test-default$'; then
  echo "FAIL: Container not running"
  docker rm -f test-default
  rm -rf holo-data
  exit 1
fi

# Check logs for success message
if ! docker logs test-default 2>&1 | grep -q "Conductor ready."; then
  echo "FAIL: No 'Conductor ready.' in logs"
  docker rm -f test-default
  rm -rf holo-data
  exit 1
fi

# Check for holochain process
if ! docker top test-default 2>&1 | grep -q holochain; then
  echo "FAIL: No holochain process running"
  docker rm -f test-default
  rm -rf holo-data
  exit 1
fi

echo "PASS: Default conductor test successful"

# Cleanup
docker rm -f test-default
rm -rf holo-data || true