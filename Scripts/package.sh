#!/usr/bin/env bash
set -euo pipefail

# Build an ad-hoc-signed app and an unsigned installer without paid certificates.
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tokenowl-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

bash Scripts/install.sh --prefix "$STAGING_DIR"
APP="$STAGING_DIR/TokenOwl.app"
cp LICENSE "$APP/Contents/Resources/LICENSE"
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
mkdir -p "$PROJECT_ROOT/DIST"
PACKAGE="$PROJECT_ROOT/DIST/TokenOwl-$VERSION-$ARCH.pkg"
pkgbuild \
  --component "$APP" \
  --install-location /Applications \
  --identifier local.tokenowl \
  --version "$VERSION" \
  "$PACKAGE"

cp LICENSE "$PROJECT_ROOT/DIST/LICENSE"
cd "$PROJECT_ROOT/DIST"
shasum -a 256 "$(basename "$PACKAGE")" > "$(basename "$PACKAGE").sha256"
echo "Created: $PACKAGE"
