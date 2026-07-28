#!/bin/bash
# Build NoraUI and assemble a runnable .app bundle.
#
# SwiftPM produces a bare executable; a menubar app needs a bundle so macOS
# reads LSUIElement (no Dock tile) and the usage strings, and so notifications
# and login items have a stable bundle identifier to attach to.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="${1:-release}"
APP_NAME="NoraUI"
BUNDLE="$SCRIPT_DIR/dist/$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
    echo "Build produced no executable at $BINARY" >&2
    exit 1
fi

echo "==> Assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Regenerate the icon when the generator is newer than the .icns, so editing
# the artwork does not silently ship the previous build's icon.
if [[ ! -f "$SCRIPT_DIR/Resources/Nora.icns" ||
      "$SCRIPT_DIR/Resources/make_icon.swift" -nt "$SCRIPT_DIR/Resources/Nora.icns" ]]; then
    echo "==> Dựng lại icon"
    (cd "$SCRIPT_DIR" \
        && swift Resources/make_icon.swift Resources/Nora.iconset > /dev/null \
        && iconutil -c icns Resources/Nora.iconset -o Resources/Nora.icns)
fi
cp "$SCRIPT_DIR/Resources/Nora.icns" "$BUNDLE/Contents/Resources/Nora.icns"

cat > "$BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Nora</string>
    <key>CFBundleDisplayName</key>
    <string>Nora</string>
    <key>CFBundleExecutable</key>
    <string>NoraUI</string>
    <key>CFBundleIdentifier</key>
    <string>com.nora.ui</string>
    <key>CFBundleIconFile</key>
    <string>Nora</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Nora cần quyền này để mở thư mục trong Finder.</string>
</dict>
PLIST
echo "</plist>" >> "$BUNDLE/Contents/Info.plist"

# Ad-hoc signature. Without any signature at all macOS refuses to launch an
# arm64 binary; ad-hoc is enough for a locally built, personal app.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || {
    echo "codesign failed; the app may not launch" >&2
}

echo "==> Done: $BUNDLE"
echo "    Chạy:  open \"$BUNDLE\""
