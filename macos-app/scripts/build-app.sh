#!/usr/bin/env bash
# Builds SwiftPM Cloak.app variant(s), embeds Xray-core + PyInstaller listener.
#
# Outputs under macos-app/dist/ (default BUILD_VARIANT=universal):
#   Cloak-arm64.app   — Apple Silicon only
#   Cloak-x86_64.app  — Intel only
#   Cloak.app         — universal (recommended for distribution)
#
# Override: BUILD_VARIANT=arm64|x86_64|universal|all
#   SKIP_SPM_CLEAN=1  — keep SwiftPM .build between runs (faster incremental)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_TARGET="SNISpoofing"
APP_NAME="Cloak"
BUNDLE_ID="${BUNDLE_ID:-io.github.snispoofinggui.cloak}"
DIST="$ROOT/dist"
BUILD_VARIANT="${BUILD_VARIANT:-universal}"
VERSION="${VERSION:-1.1.0}"
VENDOR_XRAY="$ROOT/bundle/xray"

ensure_release_assets() {
  local need_vendor=0
  local need_wheel=0

  if [[ ! -x "$VENDOR_XRAY/xray" || ! -f "$VENDOR_XRAY/geoip.dat" || ! -f "$VENDOR_XRAY/geosite.dat" ]]; then
    need_vendor=1
  fi
  if ! compgen -G "$ROOT/assets/scapy-*.whl" >/dev/null 2>&1; then
    need_wheel=1
  fi

  if [[ "$need_vendor" -eq 0 && "$need_wheel" -eq 0 ]]; then
    return
  fi

  if [[ "${SKIP_ASSETS:-0}" == "1" ]]; then
    echo "error: release assets are missing and SKIP_ASSETS=1." >&2
    echo "  Expected: $VENDOR_XRAY/{xray,geoip.dat,geosite.dat}" >&2
    echo "  Expected: $ROOT/assets/scapy-*.whl" >&2
    echo "  Run: $ROOT/scripts/fetch-release-assets.sh && $ROOT/scripts/fetch-xray-vendor.sh" >&2
    exit 1
  fi

  echo "→ release assets missing; preparing Xray/scapy assets"
  "$ROOT/scripts/fetch-release-assets.sh"
  "$ROOT/scripts/fetch-xray-vendor.sh"
}

# Interrupting the script can corrupt SwiftPM's `.build`. Retry guards
# against a Spotlight / fseventsd race that occasionally lands a new file
# in the directory mid-delete and aborts a strict `rm -rf` under `set -e`.
if [[ "${SKIP_SPM_CLEAN:-}" != "1" ]]; then
  echo "→ removing SwiftPM .build (avoids corrupted incremental state)"
  for _ in 1 2 3; do
    rm -rf "$ROOT/.build" 2>/dev/null && break
    sleep 0.5
  done
  rm -rf "$ROOT/.build" 2>/dev/null || true
fi

if [[ -f "$ROOT/logo/Cloak.png" ]]; then
  cp -f "$ROOT/logo/Cloak.png" "$ROOT/Sources/SNISpoofing/Resources/Cloak.png"
fi

# Regenerate the squircle .icns so Finder/Dock show proper rounded icon.
if [[ -x "$ROOT/scripts/make-icns.sh" && -f "$ROOT/logo/Cloak.png" ]]; then
  echo "→ rebuilding Cloak.icns (squircle)"
  "$ROOT/scripts/make-icns.sh"
fi

ensure_release_assets

# Frozen listener binaries (PyInstaller). Build if missing.
if [[ ! -x "$ROOT/bundle/cloak-core-arm64" && ! -x "$ROOT/bundle/cloak-core-x86_64" ]]; then
  echo "→ cloak-core missing; building with PyInstaller"
  "$ROOT/scripts/build-core.sh"
fi

echo "→ swift build (arm64)"
swift build --package-path "$ROOT" -c release \
  --triple arm64-apple-macosx13.0 \
  --disable-sandbox
ARM_BIN="$(find "$ROOT/.build" -path '*arm64*release*' -name "$SWIFT_TARGET" -type f -not -path '*dSYM*' | head -1)"

echo "→ swift build (x86_64)"
swift build --package-path "$ROOT" -c release \
  --triple x86_64-apple-macosx13.0 \
  --disable-sandbox
X86_BIN="$(find "$ROOT/.build" -path '*x86_64*release*' -name "$SWIFT_TARGET" -type f -not -path '*dSYM*' | head -1)"

if [[ -z "$ARM_BIN" || -z "$X86_BIN" ]]; then
  echo "error: couldn't locate swift build outputs" >&2
  exit 1
fi

if [[ ! -x "$VENDOR_XRAY/xray" || ! -f "$VENDOR_XRAY/geoip.dat" || ! -f "$VENDOR_XRAY/geosite.dat" ]]; then
  echo "error: missing vendored Xray files." >&2
  echo "  Run: $ROOT/scripts/fetch-xray-vendor.sh" >&2
  echo "  Expected: $VENDOR_XRAY/{xray,geoip.dat,geosite.dat}" >&2
  exit 1
fi

# Extract one arch from a universal xray, or copy if already single-arch for that slice.
_xray_thin() {
  local arch="$1"   # arm64 | x86_64
  local out="$2"
  if lipo -extract "$arch" "$VENDOR_XRAY/xray" -output "$out" 2>/dev/null; then
    :
  else
    local have
    have=$(lipo -archs "$VENDOR_XRAY/xray" 2>/dev/null | tr '\n' ' ' || true)
    if echo " $have " | grep -q " $arch " && [[ $(echo $have | wc -w | tr -d ' ') -eq 1 ]]; then
      cp "$VENDOR_XRAY/xray" "$out"
    else
      echo "error: $VENDOR_XRAY/xray has no $arch slice (need universal or $arch xray)" >&2
      exit 1
    fi
  fi
  chmod +x "$out"
}

assemble_one() {
  local stem="$1"       # e.g. Cloak-arm64 (bundle name = stem.app)
  local swift_bin="$2"  # path to single-arch or we'll lipo for universal
  local xray_src="$3"   # path to xray binary to embed
  local plist_id="$4"
  local bundle_dir="$5" # dirname for *.bundle copy

  local APP="$DIST/$stem.app"
  echo "→ assembling $APP"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

  cp "$swift_bin" "$APP/Contents/MacOS/$APP_NAME"
  chmod +x "$APP/Contents/MacOS/$APP_NAME"

  cp "$xray_src" "$APP/Contents/Resources/xray"
  cp "$VENDOR_XRAY/geoip.dat" "$APP/Contents/Resources/geoip.dat"
  cp "$VENDOR_XRAY/geosite.dat" "$APP/Contents/Resources/geosite.dat"
  chmod +x "$APP/Contents/Resources/xray"

  for b in "$bundle_dir"/*.bundle; do
    [[ -e "$b" ]] || continue
    cp -R "$b" "$APP/Contents/Resources/"
  done

  # macOS reads the dock/Finder icon directly from Contents/Resources/Cloak.icns
  # (via CFBundleIconFile). Keep a copy at the bundle root — not just in the
  # SwiftPM resource sub-bundle.
  if [[ -f "$ROOT/Sources/SNISpoofing/Resources/Cloak.icns" ]]; then
    cp "$ROOT/Sources/SNISpoofing/Resources/Cloak.icns" "$APP/Contents/Resources/Cloak.icns"
  fi
  if [[ -f "$ROOT/Sources/SNISpoofing/Resources/Cloak.png" ]]; then
    cp "$ROOT/Sources/SNISpoofing/Resources/Cloak.png" "$APP/Contents/Resources/Cloak.png"
  fi

  # PyInstaller-frozen listener (per-arch; do not lipo — see build-core.sh).
  CORE_COPIED=0
  for arch in arm64 x86_64; do
    src="$ROOT/bundle/cloak-core-$arch"
    if [[ -x "$src" ]]; then
      cp "$src" "$APP/Contents/Resources/cloak-core-$arch"
      chmod +x "$APP/Contents/Resources/cloak-core-$arch"
      CORE_COPIED=$((CORE_COPIED + 1))
    fi
  done
  if [[ "$CORE_COPIED" -eq 0 ]]; then
    echo "error: no cloak-core-* binaries in $ROOT/bundle/ — run scripts/build-core.sh" >&2
    exit 1
  fi
  if [[ "$CORE_COPIED" -lt 2 ]]; then
    echo "⚠︎  only $CORE_COPIED/2 listener cores embedded — app will not run on the missing architecture"
  fi

  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$plist_id</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$stem</string>
    <key>CFBundleDisplayName</key><string>$stem</string>
    <key>CFBundleIconFile</key><string>Cloak</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© Cloak</string>
</dict>
</plist>
PLIST

  ENTITLEMENTS="$ROOT/scripts/entitlements.plist"
  echo "→ ad-hoc codesigning (hardened runtime)"
  codesign --force --sign - \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP/Contents/Resources/xray"
  for arch in arm64 x86_64; do
    bin="$APP/Contents/Resources/cloak-core-$arch"
    [[ -e "$bin" ]] || continue
    codesign --force --sign - \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --timestamp=none \
      "$bin"
  done
  codesign --force --sign - \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP/Contents/MacOS/$APP_NAME"
  codesign --force --sign - \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP"
  xattr -cr "$APP" 2>/dev/null || true
  codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null
  echo "✔ $APP"
}

THIN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloak-xray-thin.XXXXXX")"
cleanup_thin() { rm -rf "$THIN_DIR"; }
trap cleanup_thin EXIT

XRAY_ARM="$THIN_DIR/xray-arm64"
XRAY_X86="$THIN_DIR/xray-x86_64"
_xray_thin arm64 "$XRAY_ARM"
_xray_thin x86_64 "$XRAY_X86"

ARM_REL="$(dirname "$ARM_BIN")"
X86_REL="$(dirname "$X86_BIN")"

case "$BUILD_VARIANT" in
  arm64)
    assemble_one "${APP_NAME}-arm64" "$ARM_BIN" "$XRAY_ARM" "${BUNDLE_ID}.arm64" "$ARM_REL"
    ;;
  x86_64)
    assemble_one "${APP_NAME}-x86_64" "$X86_BIN" "$XRAY_X86" "${BUNDLE_ID}.x86_64" "$X86_REL"
    ;;
  universal)
    UNI_SWIFT="$THIN_DIR/cloak-swift-universal"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNI_SWIFT"
    chmod +x "$UNI_SWIFT"
    assemble_one "$APP_NAME" "$UNI_SWIFT" "$VENDOR_XRAY/xray" "$BUNDLE_ID" "$ARM_REL"
    ;;
  all)
    assemble_one "${APP_NAME}-arm64" "$ARM_BIN" "$XRAY_ARM" "${BUNDLE_ID}.arm64" "$ARM_REL"
    assemble_one "${APP_NAME}-x86_64" "$X86_BIN" "$XRAY_X86" "${BUNDLE_ID}.x86_64" "$X86_REL"
    UNI_SWIFT="$THIN_DIR/cloak-swift-universal"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNI_SWIFT"
    chmod +x "$UNI_SWIFT"
    assemble_one "$APP_NAME" "$UNI_SWIFT" "$VENDOR_XRAY/xray" "$BUNDLE_ID" "$ARM_REL"
    echo
    echo "✔ Done (BUILD_VARIANT=all):"
    echo "   $DIST/${APP_NAME}-arm64.app"
    echo "   $DIST/${APP_NAME}-x86_64.app"
    echo "   $DIST/${APP_NAME}.app"
    ;;
  *)
    echo "error: BUILD_VARIANT must be arm64, x86_64, universal, or all (got: $BUILD_VARIANT)" >&2
    exit 1
    ;;
esac
