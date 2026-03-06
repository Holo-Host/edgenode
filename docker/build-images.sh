#!/bin/bash

# Multi-Image Build Script for Holochain Docker Images
# Builds all available Docker images with proper tagging

set -ex

# Script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to docker directory
cd "$SCRIPT_DIR"

# Define images to build
declare -A IMAGES=(
    ["Dockerfile.hc-0.5.6"]="local-edgenode-hc-0.5.6"
    ["Dockerfile.hc-0.6.0-dev-go-pion"]="local-edgenode-hc-0.6.0-dev-go-pion"
    ["Dockerfile.unyt"]="local-edgenode-unyt"
)

# Build images based on command line arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 [image-name] [all]"
    echo "Build specific image or all images:"
    echo "  local-edgenode-hc-0.5.6"
    echo "  local-edgenode-hc-0.6.0-dev-go-pion"
    echo "  local-edgenode-unyt"
    echo "  all (builds all images)"
    exit 1
fi

TARGET="${1}"

if [ "$TARGET" == "all" ]; then
    echo "Building all images..."
    for dockerfile in "${!IMAGES[@]}"; do
        image_name="${IMAGES[$dockerfile]}"
        echo "Building $image_name from $dockerfile"
        
        # Handle special case for unyt which needs hc-0.6.0 base image
        if [[ "$dockerfile" == "Dockerfile.unyt" ]]; then
            echo "Note: unyt image depends on hc-0.6.0-dev-go-pion image"
            if ! docker image inspect "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}" >/dev/null 2>&1; then
                echo "Building base image: ${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
                docker build -t "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}" . -f "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
            fi
            
            # For local builds, use the local base image, for remote builds use registry
            BASE_IMAGE="${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
            docker build -t "$image_name" . -f "$dockerfile" --build-arg BASE_IMAGE="$BASE_IMAGE"
        else
            docker build -t "$image_name" . -f "$dockerfile"
        fi
        
        echo "Successfully built $image_name"
        echo "---"
    done
elif [[ " ${!IMAGES[@]} " =~ " $TARGET " ]]; then
    echo "Building $TARGET..."
    dockerfile="$TARGET"
    image_name="${IMAGES[$TARGET]}"
    
    if [[ "$dockerfile" == "Dockerfile.unyt" ]]; then
        # Ensure base image exists for unyt
        if ! docker image inspect "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}" >/dev/null 2>&1; then
            echo "Building base image: ${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
            docker build -t "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}" . -f "Dockerfile.hc-0.6.0-dev-go-pion"
        fi
        BASE_IMAGE="${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
        docker build -t "$image_name" . -f "$dockerfile" --build-arg BASE_IMAGE="$BASE_IMAGE"
    else
        docker build -t "$image_name" . -f "$dockerfile"
    fi
    echo "Successfully built $image_name"
else
    # Try to look up by image name and convert to dockerfile
    FOUND_DOCKERFILE=""
    for dockerfile in "${!IMAGES[@]}"; do
        if [[ "${IMAGES[$dockerfile]}" == "$TARGET" ]]; then
            FOUND_DOCKERFILE="$dockerfile"
            break
        fi
    done
    
    if [[ -n "$FOUND_DOCKERFILE" ]]; then
        echo "Building $TARGET from $FOUND_DOCKERFILE..."
        dockerfile="$FOUND_DOCKERFILE"
        image_name="$TARGET"
        
        if [[ "$dockerfile" == "Dockerfile.unyt" ]]; then
            # Ensure base image exists for unyt
            if ! docker image inspect "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}" >/dev/null 2>&1; then
                echo "Building base image: ${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
                docker build -t "${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}" . -f "Dockerfile.hc-0.6.0-dev-go-pion"
            fi
            BASE_IMAGE="${IMAGES[Dockerfile.hc-0.6.0-dev-go-pion]}"
            docker build -t "$image_name" . -f "$dockerfile" --build-arg BASE_IMAGE="$BASE_IMAGE"
        else
            docker build -t "$image_name" . -f "$dockerfile"
        fi
        echo "Successfully built $image_name"
    else
        echo "Unknown image: $TARGET"
        echo "Available dockerfiles: ${!IMAGES[@]}"
        echo "Available images: ${IMAGES[@]}"
        exit 1
    fi
fi

echo "Build completed successfully!"