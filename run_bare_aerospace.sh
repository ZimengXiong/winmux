#!/bin/bash
set -euo pipefail

BARE_DIR="${AEROSPACE_BARE_DIR:-$HOME/Projects/AeroSpaceBare}"

if [ ! -d "$BARE_DIR" ]; then
    echo "Missing bare AeroSpace checkout: $BARE_DIR" >&2
    exit 1
fi

cd "$BARE_DIR"
exec ./run-debug-user-config.sh "$@"
