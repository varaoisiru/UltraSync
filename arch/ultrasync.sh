#!/bin/bash
# UltraSync launcher (Arch package) — runs the app from /usr/share/ultrasync
# with the system Python. Config/cache live in the user's XDG dirs.
exec python3 /usr/share/ultrasync/app_entry.py "$@"
