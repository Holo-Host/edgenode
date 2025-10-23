#!/bin/bash

set -ex

IMAGE_NAME=${1}
CONTAINER_NAME="edgenode-test"
TEST_DATA_DIR="holo-data-test"

if [ -z "$IMAGE_NAME" ]; then
  echo "Usage: $0 <image-name>"
  echo "e.g. for a local build: $0 local-edgenode-hc-0.5.6"
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
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  sudo rm -rf "$TEST_DATA_DIR" || true
}

trap cleanup EXIT

# Build image if it's a local build
if [[ "$IMAGE_NAME" == local-edgenode-* ]]; then
  DOCKERFILE_SUFFIX=$(echo "$IMAGE_NAME" | sed 's/^local-edgenode-//')
  DOCKERFILE="Dockerfile.${DOCKERFILE_SUFFIX}"
  if [ ! -f "$DOCKERFILE" ]; then
      echo "Dockerfile not found: $DOCKERFILE"
      exit 1
  fi
  echo "Building local image $IMAGE_NAME from $DOCKERFILE"
  docker build -t "$IMAGE_NAME" . -f "$DOCKERFILE"
fi

# Run container
mkdir -p "$TEST_DATA_DIR"
docker run -d \
  --name "$CONTAINER_NAME" \
  -v "$(pwd)/$TEST_DATA_DIR:/data" \
  --add-host host.docker.internal:host-gateway \
  "$IMAGE_NAME"

# Wait for startup
sleep 5

# Run tests using relative path from docker directory
export IMAGE_NAME
SCRIPT_DIR="$SCRIPT_DIR" ./tests/libs/bats/bin/bats tests