#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/native-dist"
ARTIFACTS_DIR="$ROOT_DIR/release-artifacts"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_NAME="B-Roll Downloader.app"
APP_DIR="$DIST_DIR/$APP_NAME"
DEFAULT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
APP_VERSION="${APP_VERSION:-$DEFAULT_VERSION}"
BUILD_CHANNEL="${BUILD_CHANNEL:-release}"
ZIP_PATH="$ARTIFACTS_DIR/B-Roll-Downloader-v${APP_VERSION}.zip"

APP_VERSION="$APP_VERSION" BUILD_CHANNEL="$BUILD_CHANNEL" "$ROOT_DIR/scripts/build-native-app.sh"

mkdir -p "$ARTIFACTS_DIR"
rm -f "$ZIP_PATH"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Packaged release zip at: $ZIP_PATH"
