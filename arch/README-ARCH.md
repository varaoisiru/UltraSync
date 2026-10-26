# UltraSync on Arch Linux

Packaging for the same UltraSync application — no separate Arch code.

## Install

- `./arch/install.sh` — builds `ultrasync-2.1.0` with makepkg from a
  local tarball of this repo (`sha256sums` is SKIP by design for the
  local source) and installs it; falls back to a manual install when
  makepkg is missing.
- Or by hand: `tar` the repo as `ultrasync-2.1.0.tar.gz` next to
  `arch/PKGBUILD` and run `makepkg -si` in that directory.

Layout after install:

| Path | Contents |
|---|---|
| `/usr/share/ultrasync/` | application package, `app_entry.py`, requirements |
| `/usr/bin/ultrasync` | launcher (system python) |
| `/usr/lib/systemd/user/ultrasync.service` | user service unit |
| `~/.config/ultrasync/config.json` | your config (created on first run) |
| `~/.cache/ultrasync/ultrasync.db` | SQLite cache + article store |

Runtime deps come from the repos: `python`, `python-fastapi`,
`python-uvicorn`. Optional: `lynx` for the article-extraction fallback.

## Run as a service

```
systemctl --user enable --now ultrasync.service
# GUI → http://127.0.0.1:8077
journalctl --user -u ultrasync -f
```

## Run by hand

```
ultrasync            # GUI server
ultrasync --tui      # terminal UI
ultrasync --once     # one full frame to stdout (smoke test)
```

Hue credentials: GUI Hue panel, the config file, or the
`HUE_BRIDGE_IP` / `HUE_API_KEY` environment variables (add them with
`systemctl --user edit ultrasync` if you run the service).
