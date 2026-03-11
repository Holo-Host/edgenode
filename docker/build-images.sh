#!/bin/bash

set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="${1:-local-edgenode}"

echo "Building $IMAGE_NAME from Dockerfile..."
docker build -t "$IMAGE_NAME" -f Dockerfile .
echo "Successfully built $IMAGE_NAME"
