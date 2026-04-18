#!/usr/bin/env bash
# Full release build: universal Xray (arm64+x86_64 lipo) + universal Cloak.app (Swift lipo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Repo: $ROOT"

echo "=== 1) Vendor universal xray + geo data ==="
"$ROOT/macos-app/scripts/fetch-xray-vendor.sh"

echo "=== 2) Build Swift + .app (arm64, x86_64, universal — default BUILD_VARIANT=all) ==="
SKIP_SPM_CLEAN="${SKIP_SPM_CLEAN:-0}" \
  "$ROOT/macos-app/scripts/build-app.sh"

echo
echo "✔ Outputs under $ROOT/macos-app/dist/:"
echo "     Cloak-arm64.app   Cloak-x86_64.app   Cloak.app"
