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

# Build the complete .iconset directly with AppKit. This intentionally avoids
# sips so icon generation does not depend on ImageIO accepting a source PNG.
# The icon generator itself is a build-time host tool, so it intentionally
# targets the host macOS version rather than the app's deployment target.
ICONSET="$BUILD_DIR/AppIcon.iconset"
ICON_GENERATOR="$BUILD_DIR/IconGenerator.swift"
ICON_GENERATOR_EXE="$BUILD_DIR/icon-generator"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

cat > "$ICON_GENERATOR" <<'SWIFT'
import AppKit
import Foundation

func drawLauncherIcon() {
    let outerRect = NSRect(x: 32, y: 32, width: 960, height: 960)
    let outer = NSBezierPath(roundedRect: outerRect, xRadius: 210, yRadius: 210)
    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.14, alpha: 1),
        NSColor(calibratedRed: 0.15, green: 0.07, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.14, alpha: 1)
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
}

func renderIcon(pixelSize: Int, path: String) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "VPXLauncherIcon", code: 1)
    }

    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    drawLauncherIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VPXLauncherIcon", code: 2)
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let files: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in files {
    try renderIcon(pixelSize: size, path: (outputDirectory as NSString).appendingPathComponent(name))
}
SWIFT

"$SWIFTC" \
  -sdk "$SDKROOT" \
  -framework AppKit \
  "$ICON_GENERATOR" \
  -o "$ICON_GENERATOR_EXE"

"$ICON_GENERATOR_EXE" "$ICONSET"
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
