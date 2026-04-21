#!/usr/bin/env bash
#
# Build and deploy the production environment.
#
# Usage:
#   source deploy/.env.production
#   ./deploy/scripts/production-apply.sh [tofu options]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to staging-apply.sh with production tfvars
exec "$SCRIPT_DIR/staging-apply.sh" "$@" --var-file=production.tfvars
