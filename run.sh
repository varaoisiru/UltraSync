#!/bin/bash
# UltraSync launcher — bootstraps a local venv on first run, then starts
# the app. All arguments pass through (e.g. ./run.sh --tui, --once).
set -e
cd "$(dirname "$0")"

VENV=".venv"
if [ ! -x "$VENV/bin/python" ]; then
    echo "Creating virtual environment…"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q -r requirements.txt
fi

exec "$VENV/bin/python" -m ultrasync "$@"
