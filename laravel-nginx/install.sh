#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/senkulabs/infracode-talker/main/laravel-nginx"
SCRIPT="setup.sh"

tmp="$(mktemp -t infracode-nginx-XXXXXX.sh)"
trap 'rm -f "$tmp"' EXIT

echo "[install] downloading $SCRIPT..."
curl -fsSL "$REPO_RAW/$SCRIPT" -o "$tmp"
chmod +x "$tmp"

if [ -t 0 ] && [ -t 1 ]; then
    "$tmp" "$@"
else
    if [ -e /dev/tty ]; then
        "$tmp" "$@" </dev/tty
    else
        echo "[install] no tty available; running non-interactively" >&2
        "$tmp" "$@"
    fi
fi
