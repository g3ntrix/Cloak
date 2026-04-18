#!/usr/bin/env bash
# Generates a macOS-style .icns from logo/Cloak.png with the standard
# Big Sur+ squircle mask + inset so Finder/Dock render it correctly.
#
# Output:
#   Sources/SNISpoofing/Resources/Cloak.icns
#   Sources/SNISpoofing/Resources/Cloak.png  (copied through unchanged)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_PNG="$ROOT/logo/Cloak.png"
RES_DIR="$ROOT/Sources/SNISpoofing/Resources"
OUT_ICNS="$RES_DIR/Cloak.icns"

[[ -f "$SRC_PNG" ]] || { echo "error: $SRC_PNG missing" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cloak-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

BASE_PNG="$TMP/icon_1024.png"

# Use Swift + CoreGraphics to render the artwork centered on a 1024 canvas
# inside the standard Apple squircle mask (inner box ≈ 824px, radius ≈ 185px).
/usr/bin/swift - "$SRC_PNG" "$BASE_PNG" <<'SWIFT'
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3,
      let srcImage = NSImage(contentsOfFile: args[1])
else {
    FileHandle.standardError.write(Data("make-icns: could not load source image\n".utf8))
    exit(1)
}

let base: CGFloat = 1024
let inset: CGFloat = 824
let offset: CGFloat = (base - inset) / 2
let radius: CGFloat = 185

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(base), height: Int(base),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: base, height: base))

// Squircle mask path.
let rect = CGRect(x: offset, y: offset, width: inset, height: inset)
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(path)
ctx.clip()

// Contain-fit the source into the inset square.
let srcSize = srcImage.size
let scale = min(inset / srcSize.width, inset / srcSize.height)
let drawW = srcSize.width * scale
let drawH = srcSize.height * scale
let drawRect = CGRect(
    x: offset + (inset - drawW) / 2,
    y: offset + (inset - drawH) / 2,
    width: drawW, height: drawH
)

var rectRef = drawRect
if let cg = srcImage.cgImage(forProposedRect: &rectRef, context: nil, hints: nil) {
    ctx.draw(cg, in: drawRect)
} else {
    // Fallback: render NSImage through NSGraphicsContext.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    srcImage.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
}
ctx.restoreGState()

guard let cgOut = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cgOut)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: args[2]))
SWIFT

ICONSET="$TMP/Cloak.iconset"
mkdir -p "$ICONSET"

# Required sizes for iconutil.
declare -a SIZES=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  px="${entry%%:*}"
  name="${entry##*:}"
  sips -s format png -z "$px" "$px" "$BASE_PNG" --out "$ICONSET/$name" >/dev/null
done

mkdir -p "$RES_DIR"
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
cp -f "$SRC_PNG" "$RES_DIR/Cloak.png"

echo "✔ $OUT_ICNS"
