#!/bin/zsh
# Builds ClipboardMgr.app and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=ClipboardMgr.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/ClipboardMgr "$APP/Contents/MacOS/ClipboardMgr"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClipboardMgr</string>
    <key>CFBundleIdentifier</key>
    <string>com.samuelrenick.clipboardmgr</string>
    <key>CFBundleName</key>
    <string>ClipboardMgr</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>ClipboardMgr uses accessibility to restore focus to the previously active text field after pasting.</string>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# Install to /Applications so macOS TCC stores the Accessibility grant
# against a stable path (ad-hoc signatures tied to ~/clipboard_mgr reset on rebuild).
echo "Copying to /Applications (may prompt for password)…"
cp -R "$APP" /Applications/

echo "Done. Launch with: open /Applications/ClipboardMgr.app"
