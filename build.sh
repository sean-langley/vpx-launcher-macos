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

# Prefer the bundled artwork, but do not let a damaged/unsupported PNG stop
# the application from building. If sips cannot read it, generate a native
# 1024x1024 source icon with AppKit and build the .icns from that instead.
ICON_SOURCE="$PWD/AppIcon.png"
if [[ ! -f "$ICON_SOURCE" ]] || ! /usr/bin/sips -g pixelWidth -g pixelHeight "$ICON_SOURCE" >/dev/null 2>&1; then
  echo "Bundled AppIcon.png is not readable by sips; generating app icon..."
  ICON_SOURCE="$BUILD_DIR/GeneratedAppIcon.png"
  ICON_GENERATOR="$BUILD_DIR/IconGenerator.swift"
  ICON_GENERATOR_EXE="$BUILD_DIR/icon-generator"

  cat > "$ICON_GENERATOR" <<'SWIFT'
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "GeneratedAppIcon.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let outerRect = NSRect(x: 32, y: 32, width: 960, height: 960)
let outer = NSBezierPath(roundedRect: outerRect, xRadius: 210, yRadius: 210)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.08, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.16, alpha: 1)
])!
background.draw(in: outer, angle: -65)

NSColor(calibratedWhite: 1.0, alpha: 0.55).setStroke()
outer.lineWidth = 10
outer.stroke()

let centered = NSMutableParagraphStyle()
centered.alignment = .center

let vpxAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 240, weight: .black),
    .foregroundColor: NSColor.white,
    .strokeColor: NSColor(calibratedWhite: 0.1, alpha: 0.9),
    .strokeWidth: -3.0,
    .paragraphStyle: centered
]
("VPX" as NSString).draw(in: NSRect(x: 85, y: 650, width: 854, height: 275), withAttributes: vpxAttrs)

let launcherAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 74, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1),
    .kern: 14,
    .paragraphStyle: centered
]
("LAUNCHER" as NSString).draw(in: NSRect(x: 80, y: 580, width: 864, height: 100), withAttributes: launcherAttrs)

// Chrome pinball.
let ballRect = NSRect(x: 394, y: 330, width: 236, height: 236)
let ball = NSBezierPath(ovalIn: ballRect)
let chrome = NSGradient(colors: [
    NSColor.white,
    NSColor(calibratedWhite: 0.70, alpha: 1),
    NSColor(calibratedWhite: 0.18, alpha: 1),
    NSColor(calibratedWhite: 0.82, alpha: 1)
])!
chrome.draw(in: ball, angle: -45)
NSColor(calibratedWhite: 1, alpha: 0.65).setStroke()
ball.lineWidth = 6
ball.stroke()

// Flippers: broad white bodies with red centers.
func drawFlipper(from a: NSPoint, to b: NSPoint) {
    let body = NSBezierPath()
    body.move(to: a)
    body.line(to: b)
    body.lineWidth = 92
    body.lineCapStyle = .round
    NSColor(calibratedWhite: 0.93, alpha: 1).setStroke()
    body.stroke()

    let inset = NSBezierPath()
    inset.move(to: a)
    inset.line(to: b)
    inset.lineWidth = 43
    inset.lineCapStyle = .round
    NSColor(calibratedRed: 0.82, green: 0.08, blue: 0.10, alpha: 1).setStroke()
    inset.stroke()
}

drawFlipper(from: NSPoint(x: 205, y: 220), to: NSPoint(x: 425, y: 300))
drawFlipper(from: NSPoint(x: 819, y: 220), to: NSPoint(x: 599, y: 300))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Unable to render generated app icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: output), options: .atomic)
SWIFT

  "$SWIFTC" \
    -sdk "$SDKROOT" \
    -framework AppKit \
    "$ICON_GENERATOR" \
    -o "$ICON_GENERATOR_EXE"

  "$ICON_GENERATOR_EXE" "$ICON_SOURCE"
fi

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
/usr/bin/sips -z 16 16       "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32       "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32       "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64       "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128     "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256     "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256     "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512     "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512     "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024   "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
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
    <string>6</string>
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
