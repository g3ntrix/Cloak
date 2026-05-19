#!/usr/bin/env bash
# End-to-end release build for Cloak.app.
#
# Orchestrates:
#   1. Prepare release assets (Xray zips + scapy wheel, cached/offline when present).
#   2. Build Cloak.app (SwiftPM, universal) + embed Xray/Python assets.
#   3. Package Cloak-<version>.dmg.
#
# Usage from macos-app/scripts:
#   VERSION=1.1.0 ./build-release.sh
#
# Usage from repo root:
#   VERSION=1.1.0 ./macos-app/scripts/build-release.sh
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_DIR/.." && pwd)"
VERSION="${VERSION:-1.1.0}"

echo "Repo:             $REPO_ROOT"
echo "macOS app:        $APP_DIR"
echo "Release version:  $VERSION"
echo

if [[ "${SKIP_ASSETS:-0}" != "1" ]]; then
  echo "=== 1) Prepare release assets ==="
  "$SCRIPTS_DIR/fetch-release-assets.sh"
  "$SCRIPTS_DIR/fetch-xray-vendor.sh"
else
  echo "=== 1) assets: skipped (SKIP_ASSETS=1) ==="
fi

echo "=== 2) Build frozen listener (PyInstaller) ==="
REQUIRE_UNIVERSAL="${REQUIRE_UNIVERSAL:-1}" "$SCRIPTS_DIR/build-core.sh"

echo "=== 3) Build universal Cloak.app ==="
SKIP_SPM_CLEAN="${SKIP_SPM_CLEAN:-0}" \
BUILD_VARIANT=universal \
VERSION="$VERSION" \
  "$SCRIPTS_DIR/build-app.sh"

echo "=== 4) Package DMG ==="
VERSION="$VERSION" "$SCRIPTS_DIR/make-dmg.sh"

echo
echo "✔ Release artifacts under $APP_DIR/dist/:"
echo "   - Cloak.app"
echo "   - Cloak-$VERSION.dmg"
