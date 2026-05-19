#!/usr/bin/env bash
# Compatibility wrapper. The real release script lives beside the other
# macOS app scripts, matching Shade's layout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/macos-app/scripts/build-release.sh"
