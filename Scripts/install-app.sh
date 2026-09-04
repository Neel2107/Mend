#!/bin/sh
set -eu

APPS_DIR="${MEND_APPS_DIR:-/Applications}"
VERSION="${MEND_VERSION:-latest}"
REPO="${MEND_REPO:-Neel2107/Mend}"
ASSET_NAME="Mend-app-aarch64-apple-darwin.tar.gz"

fail() {
  echo "error: $*" >&2
  exit 1
}

check_platform() {
  [ "$(uname -s)" = "Darwin" ] || fail "Mend requires macOS"
  [ "$(uname -m)" = "arm64" ] || fail "Mend requires an Apple silicon Mac"
}

can_write_apps_dir() {
  probe="$APPS_DIR"
  while [ ! -e "$probe" ]; do
    parent="$(dirname "$probe")"
    [ "$parent" = "$probe" ] && return 1
    probe="$parent"
  done
  [ -w "$probe" ]
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ] || can_write_apps_dir; then
    "$@"
  else
    sudo "$@"
  fi
}

release_url() {
  asset="$1"
  if [ "$VERSION" = "latest" ]; then
    echo "https://github.com/$REPO/releases/latest/download/$asset"
    return
  fi

  case "$VERSION" in
    v*) tag="$VERSION" ;;
    *) tag="v$VERSION" ;;
  esac
  echo "https://github.com/$REPO/releases/download/$tag/$asset"
}

verify_archive() {
  sums_url="$(release_url SHA256SUMS)"
  sums_path="$TEMP_DIR/SHA256SUMS"
  status="$(curl -sSL --connect-timeout 10 --retry 2 -o "$sums_path" -w '%{http_code}' "$sums_url" 2>/dev/null)" || status="000"

  [ "$status" = "200" ] || fail "could not download release checksums (HTTP $status)"

  expected="$(awk -v name="$ASSET_NAME" '$2 == name { print $1 }' "$sums_path")"
  [ -n "$expected" ] || fail "$ASSET_NAME is missing from SHA256SUMS"

  actual="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{ print $1 }')"
  [ "$actual" = "$expected" ] || fail "checksum verification failed"
  echo "Verified SHA-256: $actual"
}

check_platform

TEMP_DIR="$(mktemp -d /tmp/mend-install.XXXXXX)"
DESTINATION="$APPS_DIR/Mend.app"
STAGED_APP="$APPS_DIR/.Mend.app.staged-$$"
BACKUP_APP="$APPS_DIR/.Mend.app.backup-$$"
COMMITTED=0

cleanup() {
  rm -rf "$TEMP_DIR"
  if [ "$COMMITTED" -ne 1 ] && [ -e "$BACKUP_APP" ] && [ ! -e "$DESTINATION" ]; then
    run_privileged mv "$BACKUP_APP" "$DESTINATION" || true
  fi
  run_privileged rm -rf "$STAGED_APP" || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

ARCHIVE_PATH="${MEND_APP_ARCHIVE:-$TEMP_DIR/$ASSET_NAME}"
if [ -z "${MEND_APP_ARCHIVE:-}" ]; then
  DOWNLOAD_URL="$(release_url "$ASSET_NAME")"
  echo "Downloading $DOWNLOAD_URL"
  curl -fL --connect-timeout 10 --retry 2 "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"
  verify_archive
fi

tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"
SOURCE_APP="$TEMP_DIR/Mend.app"
[ -x "$SOURCE_APP/Contents/MacOS/Mend" ] || fail "archive does not contain Mend.app"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"

# Quit every running copy, including development builds outside /Applications,
# so the new install is the only Mend answering the shortcuts.
if pgrep -x Mend >/dev/null; then
  echo "Closing the running copy of Mend"
  osascript -e 'tell application id "com.mend.desktop" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Mend 2>/dev/null || true
fi

if [ ! -d "$APPS_DIR" ]; then
  run_privileged install -d -m 0755 "$APPS_DIR"
fi
run_privileged rm -rf "$STAGED_APP" "$BACKUP_APP"
run_privileged ditto "$SOURCE_APP" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"
run_privileged xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

if [ -e "$DESTINATION" ]; then
  run_privileged mv "$DESTINATION" "$BACKUP_APP"
fi

if ! run_privileged mv "$STAGED_APP" "$DESTINATION"; then
  if [ -e "$BACKUP_APP" ] && [ ! -e "$DESTINATION" ]; then
    run_privileged mv "$BACKUP_APP" "$DESTINATION"
  fi
  fail "installation failed; the previous version was restored"
fi

COMMITTED=1
run_privileged rm -rf "$BACKUP_APP"

echo "Installed Mend at $DESTINATION"
echo "Launch it with: open \"$DESTINATION\""
