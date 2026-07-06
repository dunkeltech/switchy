#!/bin/bash
# Builds Switchy in Release mode and packs it into an installable DMG.
#
# Notarization is intentionally skipped: the app is only ad-hoc signed
# (CODE_SIGN_IDENTITY = "-"). Users see a Gatekeeper warning on first launch and must
# confirm via right-click -> "Open" – see the README section "Installation for buyers".
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
BUILD_DIR="$(pwd)/build"
APP_NAME="Switchy"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Cleaning old build folder"
rm -rf "$BUILD_DIR"

echo "==> Building Release configuration (version $VERSION)"
# LD/LDPLUSPLUS: in a nix shell LD=ld would otherwise override Xcode's linker driver
# (see project notes) – reset it explicitly to clang here.
xcodebuild -project Switchy.xcodeproj -scheme Switchy -configuration Release \
  SYMROOT="$BUILD_DIR" LD=clang LDPLUSPLUS=clang++ \
  build

APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH was not produced." >&2
  exit 1
fi

echo "==> Building DMG staging directory"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Put the volume icon (logo) into the DMG.
VOLICON="$(pwd)/branding/Switchy.icns"
if [ -f "$VOLICON" ]; then
  cp "$VOLICON" "$STAGING/.VolumeIcon.icns"
fi

DMG_PATH="$BUILD_DIR/$DMG_NAME"
TMP_DMG="$BUILD_DIR/${APP_NAME}-rw.dmg"
rm -f "$DMG_PATH" "$TMP_DMG"

echo "==> Creating writable intermediate DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDRW "$TMP_DMG"

if [ -f "$VOLICON" ]; then
  echo "==> Setting volume icon"
  MOUNT_DIR="$(mktemp -d)"
  hdiutil attach "$TMP_DMG" -nobrowse -mountpoint "$MOUNT_DIR" >/dev/null
  # Set the custom-icon attribute on the volume so Finder shows the logo.
  SetFile -a C "$MOUNT_DIR" || true
  hdiutil detach "$MOUNT_DIR" >/dev/null
  rmdir "$MOUNT_DIR" 2>/dev/null || true
fi

echo "==> Compressing to $DMG_NAME"
hdiutil convert "$TMP_DMG" -format UDZO -ov -o "$DMG_PATH" >/dev/null
rm -f "$TMP_DMG"

echo ""
echo "Done: $DMG_PATH"
