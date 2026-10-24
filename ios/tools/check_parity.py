#!/usr/bin/env python3
"""Parity check: the iOS theme palettes must match ultrasync/themes.py.

Imports the canonical THEMES dict from the Python package and extracts
the ThemePalette literals from ThemeEngine.swift, then compares every
hex value (bg, primary, accent1, accent2, accent3, dim) plus display
names for all themes present in themes.py.

Usage: python3 ios/tools/check_parity.py
Exit code 0 = parity holds, 1 = mismatch (details on stdout).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # repo root
SWIFT = ROOT / "ios" / "UltraSync" / "UltraSync" / "Theme" / "ThemeEngine.swift"
FIELDS = ["bg", "primary", "accent1", "accent2", "accent3", "dim"]

sys.path.insert(0, str(ROOT))
from ultrasync.themes import THEMES  # noqa: E402  (canonical source of truth)


def parse_swift(path: Path):
    text = path.read_text(encoding="utf-8")
    palettes = {}
    # Each palette is a single ThemePalette(...) literal in ThemeCatalog.all.
    for m in re.finditer(r'ThemePalette\(id:\s*"([^"]+)",\s*name:\s*"([^"]+)"([^)]*)\)', text):
        tid, name, rest = m.group(1), m.group(2), m.group(3)
        fields = dict(re.findall(r'(\w+):\s*"(#[0-9a-fA-F]{6})"', rest))
        palettes[tid] = {"name": name, **fields}
    return palettes


def main():
    swift = parse_swift(SWIFT)
    problems = []
    for tid, py in THEMES.items():
        if tid not in swift:
            problems.append(f"{tid}: missing from ThemeEngine.swift")
            continue
        sw = swift[tid]
        if sw["name"] != py["name"]:
            problems.append(f"{tid}.name: swift={sw['name']!r} python={py['name']!r}")
        for f in FIELDS:
            if sw.get(f, "").lower() != py[f].lower():
                problems.append(f"{tid}.{f}: swift={sw.get(f)} python={py[f]}")
    extra = sorted(set(swift) - set(THEMES))
    if extra:
        problems.append(f"extra themes in Swift not in themes.py: {extra}")

    if problems:
        print("PARITY FAIL:")
        for p in problems:
            print("  -", p)
        return 1
    n = len(THEMES)
    print(f"PARITY OK: {n} themes x {len(FIELDS)} hex fields + names match themes.py exactly")
    for tid in THEMES:
        print(f"  {tid:<12} bg={THEMES[tid]['bg']} primary={THEMES[tid]['primary']} "
              f"accent1={THEMES[tid]['accent1']} accent2={THEMES[tid]['accent2']} "
              f"accent3={THEMES[tid]['accent3']} dim={THEMES[tid]['dim']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
