#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/Mend.app"
CONFIGURATION="${CONFIGURATION:-release}"

cd "$PROJECT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/$CONFIGURATION/Mend" "$APP_DIR/Contents/MacOS/Mend"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.mend.desktop"' \
  "$APP_DIR"
echo "$APP_DIR"
