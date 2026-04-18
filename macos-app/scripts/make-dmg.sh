#!/usr/bin/env bash
# Packages Cloak.app into a compressed .dmg for distribution.
# Output: macos-app/dist/Cloak-1.0.0.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Cloak.app"
VERSION="${VERSION:-1.0.0}"
DMG="$ROOT/dist/Cloak-$VERSION.dmg"
STAGING="$ROOT/dist/dmg-staging"

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found; run scripts/build-app.sh first" >&2
  exit 1
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "→ creating $DMG"
hdiutil create \
  -volname "SNI Spoofing" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "✔ $DMG"
