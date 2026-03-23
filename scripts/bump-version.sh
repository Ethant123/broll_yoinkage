#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/bump-version.sh <version>"
  exit 1
fi

NEW_VERSION="$1"

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 1.2.3"
  exit 1
fi

echo "$NEW_VERSION" > "$VERSION_FILE"
echo "Updated VERSION to $NEW_VERSION"
echo "Next:"
echo "  1. git add VERSION"
echo "  2. git commit -m \"Release v$NEW_VERSION\""
echo "  3. git push"
echo "  4. git tag v$NEW_VERSION"
echo "  5. git push origin v$NEW_VERSION"
