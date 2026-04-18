#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) 'xray' binary and copies geoip/geosite into bundle/xray.
# Prefer local zip files (no network). Optional curl fallback per zip if missing.
set -euo pipefail

XRAY_VERSION="${XRAY_VERSION:-v26.3.27}"
MACOS_APP="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_APP/.." && pwd)"
OUT="$MACOS_APP/bundle/xray"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/xray-lipo.XXXXXX")"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ARM_ASSET="Xray-macos-arm64-v8a.zip"
X86_ASSET="Xray-macos-64.zip"
URL_BASE="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"

mkdir -p "$OUT"

# Resolve an asset zip: explicit env, third_party drop, optional legacy path, then curl.
# Usage: resolve_zip VAR_ARM64_PATH VAR_X86_PATH asset_filename
resolve_zip() {
  local envpath="$1"
  local asset="$2"
  local candidate paths
  paths=(
    "${envpath:-}"
    "$MACOS_APP/assets/$asset"
    "$MACOS_APP/third_party/xray-zips/$asset"
    "$REPO_ROOT/macos-app/third_party/xray-zips/$asset"
  )
  for candidate in "${paths[@]}"; do
    [[ -n "${candidate:-}" && -f "$candidate" ]] || continue
    echo "$candidate"
    return 0
  done
  local dest="$WORKDIR/$asset"
  echo "Downloading $URL_BASE/$asset …" >&2
  if ! curl -fsSL --retry 5 --retry-delay 2 "$URL_BASE/$asset" -o "$dest"; then
    echo "error: missing $asset and curl failed. Place the file at:" >&2
    echo "  $MACOS_APP/assets/$asset" >&2
    echo "  (or run ./macos-app/scripts/fetch-release-assets.sh)" >&2
    exit 1
  fi
  echo "$dest"
}

ARM_ZIP="$(resolve_zip "${LOCAL_XRAY_ZIP_ARM64:-}" "$ARM_ASSET")"
X86_ZIP="$(resolve_zip "${LOCAL_XRAY_ZIP_X86:-}" "$X86_ASSET")"

echo "Using ARM zip:  $ARM_ZIP"
echo "Using x86 zip:  $X86_ZIP"

mkdir -p "$WORKDIR/arm64.unz" "$WORKDIR/x64.unz"
unzip -oq "$ARM_ZIP" -d "$WORKDIR/arm64.unz"
unzip -oq "$X86_ZIP" -d "$WORKDIR/x64.unz"

ARM_BIN="$WORKDIR/arm64.unz/xray"
X86_BIN="$WORKDIR/x64.unz/xray"
[[ -x "$ARM_BIN" && -x "$X86_BIN" ]] || {
  echo "error: expected xray binary inside both zips" >&2
  exit 1
}

echo "→ lipo (universal xray)"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$OUT/xray"
chmod +x "$OUT/xray"

# geo files are architecture-neutral — take from arm64 package
cp "$WORKDIR/arm64.unz/geoip.dat" "$OUT/geoip.dat"
cp "$WORKDIR/arm64.unz/geosite.dat" "$OUT/geosite.dat"

echo
echo "✔ universal xray → $OUT/xray"
file "$OUT/xray" || true
echo "✔ $OUT/geoip.dat  $OUT/geosite.dat"
