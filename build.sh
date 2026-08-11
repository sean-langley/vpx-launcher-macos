#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

APP_NAME="VPX Launcher"
BUNDLE_ID="local.vpxlauncher.app"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
EXE="$APP/Contents/MacOS/VPXLauncher"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx${DEPLOYMENT_TARGET}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode or the Xcode Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
fi

SWIFTC="$(xcrun --find swiftc)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR"

# Build the macOS .icns from the original launcher artwork bundled with the
# project. Keep AppIcon.png as the canonical icon; do not redraw it at build
# time so the app always retains the original VPX Launcher artwork.
ICON_SOURCE="$PWD/AppIcon.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "error: missing $ICON_SOURCE" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
/usr/bin/sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>VPXLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>8</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>$DEPLOYMENT_TARGET</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Swift compiler: $SWIFTC"
"$SWIFTC" --version
echo "macOS SDK:      $SDKROOT"
echo "Deployment:     macOS $DEPLOYMENT_TARGET ($TARGET)"
echo

# Validate the requested deployment target before doing the full compile. This
# catches mismatched/incomplete Command Line Tools with a clear message rather
# than silently producing an app that only runs on the build host's macOS.
TARGET_PROBE="$BUILD_DIR/TargetProbe.swift"
print 'import Foundation\n' > "$TARGET_PROBE"
if ! "$SWIFTC" -sdk "$SDKROOT" -target "$TARGET" -typecheck "$TARGET_PROBE" >/dev/null 2>&1; then
  echo "error: this Swift toolchain cannot compile for $TARGET" >&2
  echo "The selected toolchain is: $SWIFTC" >&2
  echo "Select a full Xcode installation with xcode-select, or set MACOSX_DEPLOYMENT_TARGET to a supported version." >&2
  exit 1
fi

"$SWIFTC" \
  -O \
  -parse-as-library \
  -sdk "$SDKROOT" \
  -target "$TARGET" \
  -framework SwiftUI \
  -framework AppKit \
  Sources/*.swift \
  -o "$EXE"

/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null

printf '\nBuilt:\n  %s\n\n' "$APP"
printf 'Open it with:\n  open %q\n\n' "$APP"
