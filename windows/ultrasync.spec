# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for a standalone UltraSync executable.

Build (from the repo root, inside the venv):
    .venv\\Scripts\\pyinstaller windows\\ultrasync.spec
Produces dist\\UltraSync\\UltraSync.exe (onedir). The web GUI assets are
bundled under ultrasync/web, matching api._web_dir()'s frozen path.
"""
from PyInstaller.utils.hooks import collect_submodules

hidden = (
    collect_submodules("uvicorn")
    + collect_submodules("fastapi")
    + ["ultrasync.api", "ultrasync.tui", "ultrasync.service"]
)

a = Analysis(
    ["..\\app_entry.py"],
    pathex=[".."],
    binaries=[],
    datas=[("..\\ultrasync\\web", "ultrasync\\web")],
    hiddenimports=hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["pytest", "tkinter"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="UltraSync",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # server logs + TUI need the console
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="UltraSync",
)
