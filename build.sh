#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

APP_NAME="VPX Launcher"
BUNDLE_ID="local.vpxlauncher.app"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
EXE="$APP/Contents/MacOS/VPXLauncher"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
fi

SWIFTC="$(xcrun --find swiftc)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Build the macOS .icns from the bundled source artwork.
# iconutil and sips are part of macOS, so no extra tooling is required.
ICON_SOURCE="$PWD/AppIcon.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
if [[ -f "$ICON_SOURCE" ]]; then
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
fi

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
    <string>5</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Swift compiler: $SWIFTC"
"$SWIFTC" --version
echo "macOS SDK:      $SDKROOT"
echo

# Build for the host Mac. Do not force a target triple here: recent
# Command Line Tools installations can fail to locate the Swift standard
# library when swiftc is given an explicit older macOS target even though
# the native host target works correctly.
"$SWIFTC" \
  -O \
  -parse-as-library \
  -sdk "$SDKROOT" \
  -framework SwiftUI \
  -framework AppKit \
  Sources/*.swift \
  -o "$EXE"

/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null

printf '\nBuilt:\n  %s\n\n' "$APP"
printf 'Open it with:\n  open %q\n\n' "$APP"
