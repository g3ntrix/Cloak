#!/usr/bin/env bash
# Release build for GitHub: universal Cloak.app + versioned DMG.
#
# Usage:
#   VERSION=1.0.0 ./scripts/build-release.sh
#
# Optional:
#   SKIP_SPM_CLEAN=1 VERSION=1.0.0 ./scripts/build-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"

echo "Repo: $ROOT"
echo "Release version: $VERSION"

echo "=== 1) Vendor universal xray + geo data ==="
"$ROOT/macos-app/scripts/fetch-xray-vendor.sh"

echo "=== 2) Build universal Cloak.app ==="
SKIP_SPM_CLEAN="${SKIP_SPM_CLEAN:-0}" \
BUILD_VARIANT=universal \
  "$ROOT/macos-app/scripts/build-app.sh"

echo "=== 3) Package DMG ==="
VERSION="$VERSION" "$ROOT/macos-app/scripts/make-dmg.sh"

echo
echo "✔ Release artifacts under $ROOT/macos-app/dist/:"
echo "   - Cloak.app"
echo "   - Cloak-$VERSION.dmg"
