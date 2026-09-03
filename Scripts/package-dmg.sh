#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DMG_PATH="$PROJECT_DIR/dist/Mend-$VERSION-apple-silicon.dmg"
STAGING_DIR="$(mktemp -d /tmp/mend-dmg.XXXXXX)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

APP_PATH="$(
  VERSION="$VERSION" \
  BUILD_NUMBER="$BUILD_NUMBER" \
  TARGET_TRIPLE="arm64-apple-macosx13.0" \
  SIGN_IDENTITY="$SIGN_IDENTITY" \
  "$SCRIPT_DIR/build-app.sh"
)"

ditto "$APP_PATH" "$STAGING_DIR/Mend.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Mend" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >&2

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH" >&2
echo "$DMG_PATH"
