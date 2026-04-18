#!/usr/bin/env bash
# Download Xray macOS zips + scapy wheel into macos-app/assets/ for offline release builds.
#
# Default: only downloads what is missing. Set FORCE=1 to re-fetch everything.
set -euo pipefail

MACOS_APP="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$MACOS_APP/assets"
XRAY_VERSION="${XRAY_VERSION:-v26.3.27}"
URL_BASE="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"

ARM_ASSET="Xray-macos-arm64-v8a.zip"
X86_ASSET="Xray-macos-64.zip"

mkdir -p "$ASSETS"

download() {
  local name="$1"
  local dest="$ASSETS/$name"
  echo "→ $name"
  curl -fsSL --retry 5 --retry-delay 2 "$URL_BASE/$name" -o "$dest"
}

if [[ -n "${FORCE:-}" ]] || [[ ! -f "$ASSETS/$ARM_ASSET" ]]; then
  download "$ARM_ASSET"
else
  echo "skip (exists): $ASSETS/$ARM_ASSET"
fi
if [[ -n "${FORCE:-}" ]] || [[ ! -f "$ASSETS/$X86_ASSET" ]]; then
  download "$X86_ASSET"
else
  echo "skip (exists): $ASSETS/$X86_ASSET"
fi

if [[ -n "${FORCE:-}" ]] || ! compgen -G "$ASSETS/scapy-*.whl" >/dev/null 2>&1; then
  echo "→ scapy wheel"
  rm -f "$ASSETS"/scapy-*.whl
  python3 -m pip download --only-binary=:all: --dest "$ASSETS" scapy
else
  echo "skip (exists): scapy-*.whl in $ASSETS"
fi

echo
echo "✔ Assets ready under $ASSETS"
ls -la "$ASSETS"
