#!/bin/bash

set -e

# Idempotent cleanup
if docker ps -a --format '{{.Names}}' | grep -q '^test-default$'; then
  docker rm -f test-default
fi
# Use host-owned test dir
TEST_DATA_DIR="holo-data-test"
rm -rf "$TEST_DATA_DIR" || true

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
  echo "Container logs:"
  docker logs test-default 2>&1 || true
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Check logs for success message
if ! docker logs test-default 2>&1 | grep -q "Conductor ready."; then
  echo "FAIL: No 'Conductor ready.' in logs"
  echo "Container logs:"
  docker logs test-default 2>&1 || true
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Check for holochain process
if ! docker top test-default 2>&1 | grep -q holochain; then
  echo "FAIL: No holochain process running"
  echo "Container logs:"
  docker logs test-default 2>&1 || true
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Test ownership fix for copied files
docker cp docker/kando.json test-default:/home/nonroot/
docker restart test-default
sleep 5  # Extra time for entrypoint and conductor startup post-restart

if ! docker exec test-default ls -la /home/nonroot/kando.json | grep -q "nonroot nonroot"; then
  echo "FAIL: Copied file not chowned to nonroot"
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

if ! docker logs test-default 2>&1 | grep -q "Chowned /home/nonroot contents"; then
  echo "FAIL: No chown log message"
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

if ! docker exec -u nonroot test-default sh -c "echo 'test' >> /home/nonroot/kando_config.json 2>/dev/null && echo 'Write succeeded'"; then
  echo "FAIL: Nonroot cannot write to copied file"
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

echo "PASS: Ownership fix test successful"

# Test happ installation as nonroot
echo "Testing happ installation as nonroot..."
INSTALL_OUTPUT=$(docker exec -u nonroot test-default sh -c 'cd /home/nonroot && install_happ kando.json' 2>&1)
if echo "$INSTALL_OUTPUT" | grep -q "\[✔\] App kando"; then
  echo "PASS: Happ installation successful"
  # Verify app enabled
  APPS_OUTPUT=$(docker exec -u nonroot test-default sh -c 'hc s call -r 4444 list-apps')
  echo "Apps after install: $APPS_OUTPUT"
  if echo "$APPS_OUTPUT" | grep -q "kando"; then
    echo "PASS: App listed in enabled apps"
  else
    echo "FAIL: App not listed after install"
    echo "Container logs:"
    docker logs test-default 2>&1 || true
    docker rm -f test-default
    rm -rf "$TEST_DATA_DIR"
    exit 1
  fi
else
  echo "FAIL: Happ installation failed"
  echo "Install output: $INSTALL_OUTPUT"
  # Check holochain process user
  if docker exec test-default ps aux | grep -q "holochain.*nonroot"; then
    echo "PASS: Holochain runs as nonroot"
  else
    echo "FAIL: Holochain not running as nonroot"
  fi
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

# Confirm holochain process runs as nonroot
if ! docker exec test-default ps aux | grep -q "nonroot.*holochain"; then
  echo "FAIL: Holochain process not running as nonroot"
  echo "Container logs:"
  docker logs test-default 2>&1 || true
  docker rm -f test-default
  rm -rf "$TEST_DATA_DIR"
  exit 1
fi

echo "PASS: Nonroot holochain execution confirmed"

echo "PASS: Default conductor test successful (with happ install)"

# Cleanup
docker rm -f test-default
rm -rf "$TEST_DATA_DIR" || true