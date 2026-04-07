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
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

mkdir -p "$DIST_DIR"

# ── Joining service Worker ──────────────────────────────────────────────────
#
# Entry point imports from ../joining-service/src/ relative to its own
# location. esbuild resolves these at bundle time from the repo root.
# If this fails, cross-directory imports require wrangler rather than
# esbuild alone.

echo "Building joining service Worker..."
npx esbuild \
    "$REPO_ROOT/deploy/cloudflare/worker-entry.ts" \
    --bundle \
    --format=esm \
    --platform=browser \
    --outfile="$DIST_DIR/joining.js" \
    --external:__STATIC_CONTENT_MANIFEST \
    --log-level=info

echo "  → $DIST_DIR/joining.js ($(wc -c < "$DIST_DIR/joining.js") bytes)"

# ── Log-collector Worker ────────────────────────────────────────────────────
#
# Standard TypeScript Worker with its own package.json and dependencies.
# Install deps first if node_modules is absent.

LOG_COLLECTOR_DIR="$REPO_ROOT/docker/log-collector"

if [ ! -d "$LOG_COLLECTOR_DIR/node_modules" ]; then
    echo "Installing log-collector dependencies..."
    (cd "$LOG_COLLECTOR_DIR" && npm install)
fi

echo "Building log-collector Worker..."
npx esbuild \
    "$LOG_COLLECTOR_DIR/src/index.ts" \
    --bundle \
    --format=esm \
    --platform=browser \
    --outfile="$DIST_DIR/log-collector.js" \
    --external:__STATIC_CONTENT_MANIFEST \
    --node-paths="$LOG_COLLECTOR_DIR/node_modules" \
    --log-level=info

echo "  → $DIST_DIR/log-collector.js ($(wc -c < "$DIST_DIR/log-collector.js") bytes)"

echo ""
echo "Build complete. Both bundles in $DIST_DIR/"
echo "Next: cd deploy/spike/tofu && tofu apply"
