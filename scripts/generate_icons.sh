#!/bin/bash
# Generates all app icon sizes (asset catalog) from branding/switchy_icon.svg, plus
# branding/Switchy.icns (the volume icon for the DMG) and the menu bar template icon.
#
# Requires: rsvg-convert (brew install librsvg), iconutil (Xcode tools).
set -euo pipefail

cd "$(dirname "$0")/.."

SVG="branding/switchy_icon.svg"
ICONSET_DST="Switchy/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert missing (brew install librsvg)"; exit 1; }

echo "==> Rendering PNGs from $SVG"
for s in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$TMP/png_${s}.png"
done

echo "==> Updating asset catalog ($ICONSET_DST)"
mkdir -p "$ICONSET_DST"
for s in 16 32 64 128 256 512 1024; do
  cp "$TMP/png_${s}.png" "$ICONSET_DST/icon_${s}.png"
done

echo "==> Generating branding/Switchy.icns"
ISET="$TMP/Switchy.iconset"
mkdir -p "$ISET"
cp "$TMP/png_16.png"   "$ISET/icon_16x16.png"
cp "$TMP/png_32.png"   "$ISET/icon_16x16@2x.png"
cp "$TMP/png_32.png"   "$ISET/icon_32x32.png"
cp "$TMP/png_64.png"   "$ISET/icon_32x32@2x.png"
cp "$TMP/png_128.png"  "$ISET/icon_128x128.png"
cp "$TMP/png_256.png"  "$ISET/icon_128x128@2x.png"
cp "$TMP/png_256.png"  "$ISET/icon_256x256.png"
cp "$TMP/png_512.png"  "$ISET/icon_256x256@2x.png"
cp "$TMP/png_512.png"  "$ISET/icon_512x512.png"
cp "$TMP/png_1024.png" "$ISET/icon_512x512@2x.png"
iconutil -c icns "$ISET" -o branding/Switchy.icns

echo "==> Updating menu bar icon (template)"
MB_DST="Switchy/Assets.xcassets/MenuBarIcon.imageset"
mkdir -p "$MB_DST"
rsvg-convert -w 18 -h 18 branding/switchy_menubar.svg -o "$MB_DST/menubar_18.png"
rsvg-convert -w 36 -h 36 branding/switchy_menubar.svg -o "$MB_DST/menubar_36.png"

rm -rf "$TMP"
echo "Done. Icons updated."
