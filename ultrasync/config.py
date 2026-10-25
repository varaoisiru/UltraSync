"""Unified configuration for UltraSync.

Merges the two parent config shapes:
- SolarSync: ~/.config/solarsync/config.json (nested location/preferences/
  hue/display sections)
- Ultrareader: ~/.config/ultra/config.json (flat: feeds, refresh_minutes,
  theme, enable_pi_temp, mouse_enabled, page_size)

UltraSync config lives at ~/.config/ultrasync/config.json. On first run,
any legacy parent config found is migrated into the unified shape.
Paths can be redirected with ULTRASYNC_CONFIG_DIR / ULTRASYNC_CACHE_DIR
(used by tests and portable installs).

Hue credentials come from the config file or the HUE_BRIDGE_IP /
HUE_API_KEY environment variables — never from source code.
"""
import copy
import json
import os
from pathlib import Path


def config_dir() -> Path:
    env = os.environ.get("ULTRASYNC_CONFIG_DIR")
    if env:
        return Path(env)
    return Path.home() / ".config" / "ultrasync"


def cache_dir() -> Path:
    env = os.environ.get("ULTRASYNC_CACHE_DIR")
    if env:
        return Path(env)
    return Path.home() / ".cache" / "ultrasync"


CONFIG_FILE = None  # resolved lazily via config_file()


def config_file() -> Path:
    return config_dir() / "config.json"


def cache_db() -> Path:
    return cache_dir() / "ultrasync.db"


DEFAULT_FEEDS = {
    "news": [
        ["BBC", "http://feeds.bbci.co.uk/news/rss.xml"],
        ["CBS", "https://www.cbsnews.com/latest/rss/main"],
        ["FOX", "https://feeds.foxnews.com/foxnews/latest"],
    ],
    "tech": [
        ["Ars", "https://feeds.arstechnica.com/arstechnica/index"],
        ["Verge", "https://www.theverge.com/rss/index.xml"],
        ["Wired", "https://www.wired.com/feed/rss"],
        ["TechCrunch", "https://techcrunch.com/feed/"],
    ],
    "science": [
        ["ScienceDaily", "https://www.sciencedaily.com/rss/all.xml"],
        ["NASA", "https://www.nasa.gov/rss/dyn/breaking_news.rss"],
        ["Nature", "https://www.nature.com/nature.rss"],
    ],
}

DEFAULT_CONFIG = {
    "location": {
        "auto_ip": True,
        "latitude": None,
        "longitude": None,
        "city": None,
        "timezone": "UTC",
    },
    "preferences": {
        "units": "imperial",
        "time_format": "24h",
        "refresh_minutes": 15,
        "theme": "cyberfire",
        "enable_hue": False,
        "enable_mouse": True,
        "enable_pi_temp": True,
        "page_size": 0,
    },
    "hue": {
        "bridge_ip": None,
        "api_key": None,
        "lights": [1, 6],
        "sync_conditions": False,
        "sync_mode": "conditions",
    },
    "display": {
        "show_iss": True,
        "show_planets": True,
        "show_forecast": True,
    },
    "feeds": DEFAULT_FEEDS,
    "server": {
        "host": "127.0.0.1",
        "port": 8077,
    },
}


def deep_merge(base: dict, overlay: dict) -> dict:
    """Recursively merge overlay into a copy of base."""
    out = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


def _migrate_legacy() -> dict:
    """Translate any parent-app config found on disk into the unified shape."""
    merged: dict = {}
    home = Path.home()

    # SolarSync (nested shape — mostly compatible already)
    ss_file = home / ".config" / "solarsync" / "config.json"
    if ss_file.exists():
        try:
            ss = json.loads(ss_file.read_text())
            merged = deep_merge(merged, {k: ss[k] for k in
                                         ("location", "preferences", "hue", "display")
                                         if k in ss})
        except Exception:
            pass

    # Ultrareader (flat shape)
    ur_file = home / ".config" / "ultra" / "config.json"
    if ur_file.exists():
        try:
            ur = json.loads(ur_file.read_text())
            if "feeds" in ur:
                # JSON round-trip turns feed tuples into lists already.
                merged["feeds"] = ur["feeds"]
            prefs = merged.setdefault("preferences", {})
            if "theme" in ur:
                prefs["theme"] = ur["theme"]
            if "refresh_minutes" in ur:
                prefs["refresh_minutes"] = ur["refresh_minutes"]
            if "enable_pi_temp" in ur:
                prefs["enable_pi_temp"] = ur["enable_pi_temp"]
            if "mouse_enabled" in ur:
                prefs["enable_mouse"] = ur["mouse_enabled"]
            if "page_size" in ur:
                prefs["page_size"] = ur["page_size"]
        except Exception:
            pass
    return merged


class Config:
    """Load/save the unified config with defaults + legacy migration."""

    def __init__(self, path: Path = None):
        self.path = Path(path) if path else config_file()
        self.data = copy.deepcopy(DEFAULT_CONFIG)
        self._load()

    def _load(self):
        if self.path.exists():
            try:
                on_disk = json.loads(self.path.read_text())
                self.data = deep_merge(DEFAULT_CONFIG, on_disk)
                return
            except Exception:
                pass
        # First run: migrate legacy parent configs, then persist.
        legacy = _migrate_legacy()
        if legacy:
            self.data = deep_merge(DEFAULT_CONFIG, legacy)
        self.save()

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, indent=2))

    # -- accessors -----------------------------------------------------
    def get(self, *keys, default=None):
        node = self.data
        for key in keys:
            if not isinstance(node, dict) or key not in node:
                return default
            node = node[key]
        return node

    def set(self, *keys, value):
        node = self.data
        for key in keys[:-1]:
            node = node.setdefault(key, {})
        node[keys[-1]] = value
        self.save()

    # -- hue credentials (env wins over file, neither is ever logged) ---
    def hue_bridge_ip(self):
        return os.environ.get("HUE_BRIDGE_IP") or self.get("hue", "bridge_ip")

    def hue_api_key(self):
        return os.environ.get("HUE_API_KEY") or self.get("hue", "api_key")

    def hue_configured(self) -> bool:
        return bool(self.hue_bridge_ip() and self.hue_api_key())

    def public_dict(self) -> dict:
        """Config safe to send to the GUI: credentials redacted to flags."""
        out = copy.deepcopy(self.data)
        hue = out.setdefault("hue", {})
        hue["api_key_set"] = bool(self.hue_api_key())
        hue["api_key"] = None
        hue["bridge_ip"] = self.hue_bridge_ip()
        hue["configured"] = self.hue_configured()
        return out
