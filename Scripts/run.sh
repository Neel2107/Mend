#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CURRENT_APP="$PROJECT_DIR/dist/Mend.app"

pkill -f "$CURRENT_APP/Contents/MacOS/Mend" 2>/dev/null || true
APP_PATH="$($SCRIPT_DIR/build-app.sh)"
open "$APP_PATH" --args "$@"
