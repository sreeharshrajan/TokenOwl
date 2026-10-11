#!/usr/bin/env bash
set -euo pipefail

# Builds TokenOwl in release mode and installs it as a menu-bar app bundle.
#
#   Scripts/install.sh                    # installs to /Applications
#   Scripts/install.sh --prefix ~/Applications
#
# The bundle runs as a menu-bar-only app (LSUIElement): no Dock icon, no
# main window — the owl lives in the status bar.

cd "$(dirname "$0")/.."

PREFIX="/Applications"
if [[ "${1:-}" == "--prefix" ]]; then
    PREFIX="${2:?--prefix needs a path}"
fi

echo "==> Building release"
swift build -c release --product TokenOwlApp

BIN=".build/release/TokenOwlApp"
APP="$PREFIX/TokenOwl.app"

echo "==> Assembling $APP"
mkdir -p "$PREFIX"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TokenOwlApp"
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.tokenowl</string>
    <key>CFBundleName</key>
    <string>TokenOwl</string>
    <key>CFBundleDisplayName</key>
    <string>TokenOwl</string>
    <key>CFBundleExecutable</key>
    <string>TokenOwlApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
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
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Nothing here is downloaded, but clear the flag if the tree was synced.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"

# Refresh macOS icon and LaunchServices cache for the app
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

echo "==> Installed: $APP"
echo
echo "Launch:            open \"$APP\""
echo "Start at login:    System Settings → General → Login Items → + → $APP"
echo "Uninstall:         rm -rf \"$APP\""
