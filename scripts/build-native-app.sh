#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/NativeMacApp"
BUILD_DIR="$PACKAGE_DIR/.build/release"
DIST_DIR="$ROOT_DIR/native-dist"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="B-Roll Downloader.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_NAME="B-Roll Downloader"
DEFAULT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
APP_VERSION="${APP_VERSION:-$DEFAULT_VERSION}"
BUILD_CHANNEL="${BUILD_CHANNEL:-local}"
APP_IDENTIFIER="${APP_IDENTIFIER:-com.internal.brolldownloader.native}"
RESOURCES_SOURCE_DIR="$ROOT_DIR/NativeMacApp/Resources"

swift build -c release --package-path "$PACKAGE_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -d "$RESOURCES_SOURCE_DIR" ]]; then
  cp -R "$RESOURCES_SOURCE_DIR/." "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>B-Roll Downloader</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_IDENTIFIER}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>B-Roll Downloader</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>BRollBuildChannel</key>
  <string>${BUILD_CHANNEL}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

echo "Built native app at: $APP_DIR"
