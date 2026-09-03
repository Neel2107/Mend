#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
pkill -x Mend 2>/dev/null || true
APP_PATH="$($SCRIPT_DIR/build-app.sh)"
open "$APP_PATH" --args "$@"
