"""Terminal primitives shared by the TUI (from Ultrareader).

vlen/vpad do ANSI-aware width math; InputHandler is Ultrareader's
termios reader with mouse support; get_pi_temp and open_in_browser are
kept from the original.
"""
import os
import re
import select
import subprocess
import sys
import termios
import time
import tty
from pathlib import Path
from typing import Optional

ANSI_RE = re.compile(r"\033\[[0-9;]*m")


def vlen(s: str) -> int:
    return len(ANSI_RE.sub("", s))


def vpad(s: str, width: int) -> str:
    plain = ANSI_RE.sub("", s)
    pad = width - len(plain)
    if pad > 0:
        return s + " " * pad
    if pad < 0:
        result, count, in_ansi = "", 0, False
        for ch in s:
            if ch == "\033":
                in_ansi = True
            if in_ansi:
                result += ch
                if ch == "m":
                    in_ansi = False
                continue
            if count < width:
                result += ch
                count += 1
        return result
    return s


def rel_age(ts: int) -> str:
    secs = int(time.time()) - ts
    if secs < 60:
        return "now"
    if secs < 3600:
        return f"{secs // 60}m"
    if secs < 86400:
        return f"{secs // 3600}h"
    return f"{secs // 86400}d"


_THERMAL_PATH = Path("/sys/class/thermal/thermal_zone0/temp")


def get_pi_temp() -> Optional[str]:
    try:
        raw = int(_THERMAL_PATH.read_text().strip())
        return f"CPU:{raw / 1000.0:.0f}°C"
    except Exception:
        return None


def open_in_browser(url: str) -> None:
    try:
        if sys.platform == "darwin":
            subprocess.Popen(["open", url], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        else:
            subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    except Exception:
        pass


class InputHandler:
    """Ultrareader's keyboard/mouse reader (termios, no curses)."""

    def __init__(self, mouse_enabled: bool):
        self.mouse_enabled = mouse_enabled

    def read(self, timeout: float = 0.15) -> Optional[str]:
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setcbreak(fd)
            if self.mouse_enabled:
                sys.stdout.write("\033[?1000h\033[?1002h\033[?1015h\033[?1006h")
                sys.stdout.flush()
            r, _, _ = select.select([sys.stdin], [], [], timeout)
            if not r:
                return None
            ch = sys.stdin.read(1)
            if ch == "\x1b" and self.mouse_enabled:
                seq = ch + sys.stdin.read(2)
                if seq.startswith("\x1b[M"):
                    btn = ord(sys.stdin.read(1))
                    cx = ord(sys.stdin.read(1)) - 32
                    cy = ord(sys.stdin.read(1)) - 32
                    return f"mouse:{btn}:{cx}:{cy}"
                return seq
            if ch in ("\n", "\r"):
                return "enter"
            if ch == "\x7f":
                return "backspace"
            if ch == "\x1b":
                seq = ch + sys.stdin.read(2)
                if seq == "\x1b[A":
                    return "up"
                if seq == "\x1b[B":
                    return "down"
                return "esc"
            return ch.lower()
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
            if self.mouse_enabled:
                sys.stdout.write("\033[?1006l\033[?1015l\033[?1002l\033[?1000l")
                sys.stdout.flush()
