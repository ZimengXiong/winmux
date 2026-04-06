#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if pgrep -x yabai >/dev/null 2>&1; then
    echo "warning: yabai is still running and may conflict with AeroSpace" >&2
fi

if pgrep -x skhd >/dev/null 2>&1; then
    echo "warning: skhd is still running; its yabai shortcuts will keep firing" >&2
fi

./build-debug.sh
if [ -n "${AEROSPACE_CONFIG_PATH:-}" ]; then
    if [ ! -f "$AEROSPACE_CONFIG_PATH" ]; then
        echo "Missing AeroSpace config: $AEROSPACE_CONFIG_PATH" >&2
        exit 1
    fi
    exec ./.debug/AeroSpaceApp --config-path "$AEROSPACE_CONFIG_PATH" "$@"
else
    exec ./.debug/AeroSpaceApp "$@"
fi
