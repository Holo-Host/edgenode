#!/bin/bash

set -e

# Idempotent cleanup
if docker ps -a --format '{{.Names}}' | grep -q '^test-default$'; then
  docker rm -f test-default
fi
# Use host-owned test dir
TEST_DATA_DIR="holo-data-test"
rm -rf "$TEST_DATA_DIR"

# Build image
cd docker
docker build -t local-trailblazer . -f Dockerfile
cd ..

# Run container without CONDUCTOR_MODE
mkdir -p "$TEST_DATA_DIR"
docker run -d --name test-default -v "$(pwd)/$TEST_DATA_DIR:/data" local-trailblazer

# Wait for startup
sleep 5

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q '^test-default$'; then
  echo "FAIL: Container not running"
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Check logs for success message
if ! docker logs test-default 2>&1 | grep -q "Conductor ready."; then
  echo "FAIL: No 'Conductor ready.' in logs"
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Check for holochain process
if ! docker top test-default 2>&1 | grep -q holochain; then
  echo "FAIL: No holochain process running"
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Test ownership fix for copied files
docker cp docker/kando_config.json test-default:/home/nonroot/
docker restart test-default
sleep 2

if ! docker exec test-default ls -la /home/nonroot/kando_config.json | grep -q "nonroot nonroot"; then
  echo "FAIL: Copied file not chowned to nonroot"
  docker rm -f test-default
  rm -rf holo-data
  exit 1
fi

if ! docker logs test-default 2>&1 | grep -q "Chowned /home/nonroot contents"; then
  echo "FAIL: No chown log message"
  docker rm -f test-default
  rm -rf holo-data
  exit 1
fi

if ! docker exec -u nonroot test-default sh -c "echo 'test' >> /home/nonroot/kando_config.json 2>/dev/null && echo 'Write succeeded'"; then
  echo "FAIL: Nonroot cannot write to copied file"
  docker rm -f test-default
  rm -rf holo-data
  exit 1
fi

echo "PASS: Ownership fix test successful"

echo "PASS: Default conductor test successful"

# Cleanup
docker rm -f test-default
rm -rf "$TEST_DATA_DIR" || true