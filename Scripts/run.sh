#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="$($SCRIPT_DIR/build-app.sh)"
open "$APP_PATH"
