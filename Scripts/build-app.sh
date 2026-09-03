#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/dist/Mend.app"
CONFIGURATION="${CONFIGURATION:-release}"
TARGET_TRIPLE="${TARGET_TRIPLE:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$PROJECT_DIR"

if [[ -n "$TARGET_TRIPLE" ]]; then
  SCRATCH_PATH="${SCRATCH_PATH:-$PROJECT_DIR/.build/targets/$TARGET_TRIPLE}"
  swift build \
    -c "$CONFIGURATION" \
    --triple "$TARGET_TRIPLE" \
    --scratch-path "$SCRATCH_PATH" >&2
  BINARY_PATH="$(find "$SCRATCH_PATH" -type f -path "*/$CONFIGURATION/Mend" -print -quit)"
else
  swift build -c "$CONFIGURATION" >&2
  BINARY_PATH="$PROJECT_DIR/.build/$CONFIGURATION/Mend"
fi

if [[ -z "$BINARY_PATH" || ! -f "$BINARY_PATH" ]]; then
  echo "Could not find the built Mend executable." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/Mend"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --sign - \
    --requirements '=designated => identifier "com.mend.desktop"' \
    "$APP_DIR"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
