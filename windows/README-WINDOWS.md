# UltraSync on Windows

Packaging for the same UltraSync application — no separate Windows code.

## Install (script)

1. Install Python 3.11+ from python.org (check "Add python.exe to PATH").
2. From the repo root: `windows\install.bat`
   - finds Python (`py -3` or `python`), creates `.venv`, installs
     FastAPI + uvicorn from `requirements.txt`, creates the config/cache
     directories under `%USERPROFILE%\.config\ultrasync` and
     `%USERPROFILE%\.cache\ultrasync`.

## Run

- `windows\run.bat` — starts the GUI server minimized and opens
  http://127.0.0.1:8077 in your browser.
- Terminal UI: `.venv\Scripts\python.exe -m ultrasync --tui`
- One-shot frame (smoke test): `.venv\Scripts\python.exe -m ultrasync --once`

## Standalone .exe (PyInstaller)

```
.venv\Scripts\pip install pyinstaller
.venv\Scripts\pyinstaller windows\ultrasync.spec
```

Produces `dist\UltraSync\UltraSync.exe` (onedir build; keep the whole
`dist\UltraSync` folder together — the GUI assets live beside the exe).
Config and cache still live under `%USERPROFILE%`, so the exe needs no
writable install directory.

## Notes

- Hue: set the bridge IP / API key in the GUI's Hue panel, in
  `%USERPROFILE%\.config\ultrasync\config.json`, or via the
  `HUE_BRIDGE_IP` / `HUE_API_KEY` environment variables.
- Windows Firewall may prompt the first time the server binds; the
  default bind is localhost-only (127.0.0.1), so denying is fine.
