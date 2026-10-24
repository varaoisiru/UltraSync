"""Minimal HTTP helpers shared by every data module (stdlib only).

Returns None on any failure — callers fall back to the cache, so the
app degrades gracefully offline. Set ULTRASYNC_NO_NET=1 to force
offline mode (used by tests and by users on metered links).
"""
import json
import os
import urllib.error
import urllib.request

USER_AGENT = "UltraSync/1.0 Terminal-App"


def net_disabled() -> bool:
    return os.environ.get("ULTRASYNC_NO_NET") == "1"


def fetch_bytes(url: str, timeout: int = 10, headers: dict = None):
    if net_disabled():
        return None
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": USER_AGENT, **(headers or {})})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except Exception:
        return None


def fetch_text(url: str, timeout: int = 10, headers: dict = None):
    raw = fetch_bytes(url, timeout=timeout, headers=headers)
    if raw is None:
        return None
    return raw.decode("utf-8", errors="replace")


def fetch_json(url: str, timeout: int = 10):
    text = fetch_text(url, timeout=timeout)
    if text is None:
        return None
    try:
        return json.loads(text)
    except Exception:
        return None
