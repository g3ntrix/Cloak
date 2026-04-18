#!/usr/bin/env bash
# Packages Cloak.app into a compressed .dmg for distribution.
# Output: macos-app/dist/Cloak-1.0.0.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Cloak.app"
VERSION="${VERSION:-1.0.0}"
DMG="$ROOT/dist/Cloak-$VERSION.dmg"
STAGING="$ROOT/dist/dmg-staging"
VOL_NAME="${VOL_NAME:-SNI Spoofing}"

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found; run scripts/build-app.sh first" >&2
  exit 1
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# `hdiutil create -srcfolder` can fail with "No space left on device" on larger apps
# when the temporary image is undersized. Compute explicit size with headroom.
STAGING_KB="$(du -sk "$STAGING" | awk '{print $1}')"
DMG_MB=$(( (STAGING_KB * 13 / 10) / 1024 + 128 ))
if [[ "$DMG_MB" -lt 512 ]]; then DMG_MB=512; fi

# Clean up any stale mount from a previous failed run.
hdiutil detach "/Volumes/$VOL_NAME" -quiet >/dev/null 2>&1 || true

echo "→ creating $DMG (size=${DMG_MB}m)"
hdiutil create \
  -volname "$VOL_NAME" \
  -size "${DMG_MB}m" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "✔ $DMG"
