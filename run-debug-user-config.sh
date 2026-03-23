#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG_PATH="${AEROSPACE_CONFIG_PATH:-$HOME/.config/aerospace/aerospace.toml}"

if [ ! -f "$CONFIG_PATH" ]; then
    echo "Missing AeroSpace config: $CONFIG_PATH" >&2
    exit 1
fi

if pgrep -x yabai >/dev/null 2>&1; then
    echo "warning: yabai is still running and may conflict with AeroSpace" >&2
fi

if pgrep -x skhd >/dev/null 2>&1; then
    echo "warning: skhd is still running; its yabai shortcuts will keep firing" >&2
fi

./build-debug.sh
exec ./.debug/AeroSpaceApp --config-path "$CONFIG_PATH" "$@"
