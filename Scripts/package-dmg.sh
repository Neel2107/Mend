#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DMG_PATH="$PROJECT_DIR/dist/Mend-$VERSION-apple-silicon.dmg"
STAGING_DIR="$(mktemp -d /tmp/mend-dmg.XXXXXX)"
MOUNT_DIR=""
RW_DIR="$(mktemp -d /tmp/mend-rw.XXXXXX)"
RW_DMG="$RW_DIR/Mend-rw.dmg"
BACKGROUND_PATH="$PROJECT_DIR/Resources/DMGBackground.png"
VOLUME_NAME="Mend $VERSION"

cleanup() {
  if [[ -n "$MOUNT_DIR" ]] && mount | grep -Fq "on $MOUNT_DIR "; then
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR" "$RW_DIR"
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
mkdir -p "$STAGING_DIR/.background"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/DMGBackground.png"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >&2

ATTACH_OUTPUT="$(hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  "$RW_DMG")"
print -r -- "$ATTACH_OUTPUT" >&2
MOUNT_DIR="$(print -r -- "$ATTACH_OUTPUT" | sed -n 's|^.*Apple_HFS[[:space:]]*||p' | tail -n 1)"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  echo "Could not determine the mounted DMG path." >&2
  exit 1
fi

/usr/bin/SetFile -a V "$MOUNT_DIR/.background"

osascript <<APPLESCRIPT
set backgroundFile to POSIX file "$MOUNT_DIR/.background/DMGBackground.png" as alias
set mountedVolume to POSIX file "$MOUNT_DIR" as alias

tell application "Finder"
  set targetDisk to disk of mountedVolume
  tell targetDisk
    open
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {120, 120, 820, 580}
    end tell

    set viewOptions to the icon view options of container window
    tell viewOptions
      set arrangement to not arranged
      set icon size to 112
      set text size to 14
      set label position to bottom
      set background color to {65535, 65535, 65535}
      set background picture to backgroundFile
    end tell

    set position of item "Mend.app" to {190, 210}
    set position of item "Applications" to {510, 210}
    update without registering applications
    delay 2
    close
    delay 1
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >&2
MOUNT_DIR=""
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_PATH" >&2

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH" >&2
echo "$DMG_PATH"
