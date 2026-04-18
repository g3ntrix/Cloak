#!/usr/bin/env bash
# Builds SwiftPM Cloak.app variant(s), embeds Xray-core + geo data.
#
# Outputs under macos-app/dist/ (default BUILD_VARIANT=all):
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
BUILD_VARIANT="${BUILD_VARIANT:-all}"

# Interrupting the script can corrupt SwiftPM's `.build`.
if [[ "${SKIP_SPM_CLEAN:-}" != "1" ]]; then
  echo "→ removing SwiftPM .build (avoids corrupted incremental state)"
  rm -rf "$ROOT/.build"
fi

if [[ -f "$ROOT/logo/Cloak.png" ]]; then
  cp -f "$ROOT/logo/Cloak.png" "$ROOT/Sources/SNISpoofing/Resources/Cloak.png"
fi

# Regenerate the squircle .icns so Finder/Dock show proper rounded icon.
if [[ -x "$ROOT/scripts/make-icns.sh" && -f "$ROOT/logo/Cloak.png" ]]; then
  echo "→ rebuilding Cloak.icns (squircle)"
  "$ROOT/scripts/make-icns.sh"
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

VENDOR_XRAY="$ROOT/bundle/xray"
if [[ ! -x "$VENDOR_XRAY/xray" || ! -f "$VENDOR_XRAY/geoip.dat" || ! -f "$VENDOR_XRAY/geosite.dat" ]]; then
  echo "error: missing vendored Xray files." >&2
  echo "  Run: ./macos-app/scripts/fetch-xray-vendor.sh" >&2
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

  # Embed the SNI-spoofing Python source so the app is self-contained.
  # Users no longer need to point at an external project folder.
  PY_SRC="$APP/Contents/Resources/python"
  mkdir -p "$PY_SRC"
  for f in main.py fake_tcp.py injecter.py monitor_connection.py; do
    [[ -f "$ROOT/../$f" ]] && cp "$ROOT/../$f" "$PY_SRC/$f"
  done
  if [[ -d "$ROOT/../utils" ]]; then
    rm -rf "$PY_SRC/utils"
    cp -R "$ROOT/../utils" "$PY_SRC/utils"
    find "$PY_SRC/utils" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
  fi
  if [[ -f "$ROOT/../requirements.txt" ]]; then
    cp "$ROOT/../requirements.txt" "$PY_SRC/requirements.txt"
  fi

  # Bundle scapy wheel from macos-app/assets (offline release builds — no pip at build time).
  WHEELHOUSE_ASSETS="$ROOT/assets"
  WHEELHOUSE_DST="$PY_SRC/wheelhouse"
  rm -rf "$WHEELHOUSE_DST"
  mkdir -p "$WHEELHOUSE_DST"
  if compgen -G "$WHEELHOUSE_ASSETS/scapy-*.whl" >/dev/null; then
    cp "$WHEELHOUSE_ASSETS"/scapy-*.whl "$WHEELHOUSE_DST/"
  else
    echo "error: missing scapy wheel in $WHEELHOUSE_ASSETS/scapy-*.whl" >&2
    echo "Run: ./macos-app/scripts/fetch-release-assets.sh" >&2
    exit 1
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
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
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

  codesign --force --deep --sign - "$APP/Contents/Resources/xray"
  codesign --force --deep --sign - "$APP"
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
