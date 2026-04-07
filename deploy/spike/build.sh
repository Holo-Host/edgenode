#!/usr/bin/env bash
#
# Build both Cloudflare Workers into deploy/spike/dist/ for the spike.
# Run from the repo root or from deploy/spike/.
#
# Both Workers are bundled with esbuild (the same bundler wrangler uses
# internally). Cross-directory imports in the joining service entry point
# are resolved at bundle time.
#
# If either build fails, note the error — it directly answers one of the
# spike's three questions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIONEER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

# The joining service worker entry point lives in the mewsfeed repo and
# imports from the joining-service repo (a sibling of mewsfeed).
# Override these if your checkouts are elsewhere.
MEWSFEED_DIR="${MEWSFEED_DIR:-$(cd "$PIONEER_DIR/../src/mewsfeed" && pwd 2>/dev/null || echo "")}"
JOINING_SERVICE_DIR="${JOINING_SERVICE_DIR:-$(cd "$PIONEER_DIR/../src/joining-service" && pwd 2>/dev/null || echo "")}"

if [ -z "$MEWSFEED_DIR" ] || [ ! -d "$MEWSFEED_DIR" ]; then
    echo "ERROR: mewsfeed repo not found. Set MEWSFEED_DIR to its path."
    echo "  e.g. MEWSFEED_DIR=/path/to/mewsfeed ./build.sh"
    exit 1
fi

if [ -z "$JOINING_SERVICE_DIR" ] || [ ! -d "$JOINING_SERVICE_DIR" ]; then
    echo "ERROR: joining-service repo not found. Set JOINING_SERVICE_DIR to its path."
    echo "  e.g. JOINING_SERVICE_DIR=/path/to/joining-service ./build.sh"
    exit 1
fi

# @holo-host/lair is a file: dependency with no pre-built dist/.
# Resolve it to holo-web-conductor/packages/lair and build if needed.
HOLO_WEB_CONDUCTOR_DIR="${HOLO_WEB_CONDUCTOR_DIR:-$(cd "$PIONEER_DIR/../src/holo-web-conductor" && pwd 2>/dev/null || echo "")}"
LAIR_PACKAGE_DIR="$HOLO_WEB_CONDUCTOR_DIR/packages/lair"

if [ -z "$HOLO_WEB_CONDUCTOR_DIR" ] || [ ! -d "$LAIR_PACKAGE_DIR" ]; then
    echo "ERROR: holo-web-conductor repo not found. Set HOLO_WEB_CONDUCTOR_DIR to its path."
    echo "  e.g. HOLO_WEB_CONDUCTOR_DIR=/path/to/holo-web-conductor ./build.sh"
    exit 1
fi

if [ ! -d "$LAIR_PACKAGE_DIR/dist" ]; then
    echo "Building @holo-host/lair (from $LAIR_PACKAGE_DIR)..."
    (cd "$HOLO_WEB_CONDUCTOR_DIR" && npm install && node_modules/.bin/tsc --build packages/lair/tsconfig.json)
fi

mkdir -p "$DIST_DIR"

# ── Joining service Worker ──────────────────────────────────────────────────
#
# Entry point imports from ../joining-service/src/ relative to its own
# location. esbuild resolves these at bundle time.
# If this fails, cross-directory imports require wrangler rather than
# esbuild alone.

echo "Building joining service Worker (from $MEWSFEED_DIR)..."
NODE_PATH="$JOINING_SERVICE_DIR/node_modules" npx esbuild \
    "$MEWSFEED_DIR/deploy/cloudflare/worker-entry.ts" \
    --bundle \
    --format=esm \
    --platform=browser \
    --outfile="$DIST_DIR/joining.js" \
    --external:__STATIC_CONTENT_MANIFEST \
    --external:"node:*" \
    --log-level=info

echo "  → $DIST_DIR/joining.js ($(wc -c < "$DIST_DIR/joining.js") bytes)"

# ── Log-collector Worker ────────────────────────────────────────────────────
#
# Standard TypeScript Worker with its own package.json and dependencies.
# Install deps first if node_modules is absent.

LOG_COLLECTOR_DIR="$PIONEER_DIR/docker/log-collector"

if [ ! -d "$LOG_COLLECTOR_DIR/node_modules" ]; then
    echo "Installing log-collector dependencies..."
    (cd "$LOG_COLLECTOR_DIR" && npm install)
fi

echo "Building log-collector Worker..."
NODE_PATH="$LOG_COLLECTOR_DIR/node_modules" npx esbuild \
    "$LOG_COLLECTOR_DIR/src/index.ts" \
    --bundle \
    --format=esm \
    --platform=browser \
    --outfile="$DIST_DIR/log-collector.js" \
    --external:__STATIC_CONTENT_MANIFEST \
    --external:"node:*" \
    --external:buffer \
    --log-level=info

echo "  → $DIST_DIR/log-collector.js ($(wc -c < "$DIST_DIR/log-collector.js") bytes)"

echo ""
echo "Build complete. Both bundles in $DIST_DIR/"
echo "Next: cd deploy/spike/tofu && tofu apply"
