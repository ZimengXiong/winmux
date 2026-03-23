#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
source ./script/setup.sh

CONFIG_PATH="${AEROSPACE_CONFIG_PATH:-$HOME/.config/aerospace/aerospace.toml}"
APP_ARGS=("$@")
APP_PID=""

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

watch_fingerprint() {
    {
        /usr/bin/find Sources ShellParserGenerated resources script \
            -type f \
            ! -path '*/.build/*' \
            ! -path 'Sources/Common/versionGenerated.swift' \
            ! -path 'Sources/Common/gitHashGenerated.swift' \
            ! -path 'Sources/Cli/subcommandDescriptionsGenerated.swift' \
            -exec /usr/bin/stat -f '%m %N' {} +
        /usr/bin/stat -f '%m %N' \
            Package.swift \
            Package.resolved \
            build-debug.sh \
            generate.sh \
            run-dev-user-config.sh \
            run-debug-user-config.sh \
            "$CONFIG_PATH"
    } 2>/dev/null | /usr/bin/shasum | /usr/bin/awk '{ print $1 }'
}

start_app() {
    ./.debug/AeroSpaceApp --config-path "$CONFIG_PATH" "${APP_ARGS[@]}" &
    APP_PID=$!
    echo "started AeroSpaceApp pid=$APP_PID"
}

stop_app() {
    if [ -n "${APP_PID:-}" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    APP_PID=""
}

cleanup() {
    stop_app
}

trap cleanup EXIT INT TERM

echo "building initial debug app..."
./build-debug.sh
start_app

last_fingerprint="$(watch_fingerprint)"

while true; do
    /bin/sleep 1
    next_fingerprint="$(watch_fingerprint)"
    if [ "$next_fingerprint" = "$last_fingerprint" ]; then
        continue
    fi

    last_fingerprint="$next_fingerprint"
    echo "change detected, rebuilding..."
    if ./build-debug.sh; then
        echo "build succeeded, relaunching..."
        stop_app
        start_app
    else
        echo "build failed, keeping previous app instance running if available" >&2
    fi
done
