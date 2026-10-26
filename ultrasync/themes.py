"""Unified theme engine.

One theme set drives every surface of UltraSync — the web GUI, the
terminal UI, the HTML export, and Hue sync. The eight canonical themes
are SolarSync's hex palettes; each is fused with Ultrareader's 256-color
ramp data for the same theme name (Ultrareader shipped 27 themes, and
these eight names exist in both parents with matching identities).
"""
import colorsys

# hex palette: SolarSync THEMES. ramp/border/header/active/sel_bg:
# Ultrareader THEMES (ANSI 256 codes).
THEMES = {
    "cyberfire": {
        "name": "Cyberfire",
        "bg": "#0a0a0a", "primary": "#00ff41", "accent1": "#ff6600",
        "accent2": "#ffaa00", "accent3": "#ff3300", "dim": "#006600",
        "ramp": [124, 160, 196, 202, 208, 214, 220, 214, 208, 202, 160],
        "border": 160, "header": 202, "active": 220, "sel_bg": 234,
    },
    "midnight": {
        "name": "Midnight Ice",
        "bg": "#0a0a0f", "primary": "#b0b0b0", "accent1": "#4a9eff",
        "accent2": "#00d4aa", "accent3": "#8855ff", "dim": "#333344",
        "ramp": [17, 18, 19, 20, 27, 33, 39, 33, 27, 20, 19],
        "border": 27, "header": 39, "active": 51, "sel_bg": 235,
    },
    "phosphor": {
        "name": "Phosphor Green",
        "bg": "#0a0a0a", "primary": "#33ff33", "accent1": "#00cc00",
        "accent2": "#009900", "accent3": "#66ff66", "dim": "#003300",
        "ramp": [22, 28, 34, 40, 46, 82, 118, 82, 46, 40, 34],
        "border": 28, "header": 46, "active": 82, "sel_bg": 233,
    },
    "solarflare": {
        "name": "Solar Flare",
        "bg": "#0f0a00", "primary": "#ffcc00", "accent1": "#ff6600",
        "accent2": "#ff3300", "accent3": "#ffffff", "dim": "#663300",
        "ramp": [196, 202, 208, 214, 220, 226, 220, 214, 208, 202, 196],
        "border": 196, "header": 214, "active": 220, "sel_bg": 236,
    },
    "aurora": {
        "name": "Aurora Borealis",
        "bg": "#050510", "primary": "#e0e0ff", "accent1": "#00ff88",
        "accent2": "#ff44aa", "accent3": "#44aaff", "dim": "#220033",
        "ramp": [22, 28, 34, 40, 45, 51, 87, 123, 159, 195, 231],
        "border": 22, "header": 45, "active": 87, "sel_bg": 234,
    },
    "neonviolet": {
        "name": "Neon Violet",
        "bg": "#0a0010", "primary": "#ff00ff", "accent1": "#00ffff",
        "accent2": "#ff0088", "accent3": "#8800ff", "dim": "#330044",
        "ramp": [53, 55, 57, 91, 93, 129, 93, 91, 57, 55, 53],
        "border": 53, "header": 93, "active": 129, "sel_bg": 235,
    },
    "deepocean": {
        "name": "Deep Ocean",
        "bg": "#000a10", "primary": "#00ffff", "accent1": "#0088ff",
        "accent2": "#00ff88", "accent3": "#ff8800", "dim": "#002233",
        "ramp": [17, 18, 24, 30, 36, 42, 36, 30, 24, 18, 17],
        "border": 17, "header": 30, "active": 42, "sel_bg": 234,
    },
    "toxicwaste": {
        "name": "Toxic Waste",
        "bg": "#0a0a00", "primary": "#00ff00", "accent1": "#ffff00",
        "accent2": "#ff00ff", "accent3": "#00ffff", "dim": "#333300",
        "ramp": [28, 34, 40, 46, 82, 118, 154, 118, 82, 46, 40],
        "border": 28, "header": 46, "active": 118, "sel_bg": 233,
    },
}

DEFAULT_THEME = "cyberfire"


def _load_extra_themes():
    """Merge the generated theme variations (themes_extra.json, built
    by the mesh theme pipeline: 500 palettes in the same schema as the
    canonical eight). Failure-safe by design: a missing or corrupt
    file leaves the canonical set untouched, and canonical slugs
    always win over generated ones."""
    import json
    import os
    path = os.path.join(os.path.dirname(__file__), "themes_extra.json")
    try:
        with open(path) as f:
            extra = json.load(f)
    except Exception:
        return
    if not isinstance(extra, dict):
        return
    required = {"name", "bg", "primary", "accent1", "accent2", "accent3",
                "dim", "ramp", "border", "header", "active", "sel_bg"}
    for slug, entry in extra.items():
        if slug not in THEMES and isinstance(entry, dict) \
                and required.issubset(entry.keys()):
            THEMES[slug] = entry


_load_extra_themes()


def theme_names():
    return list(THEMES.keys())


def get_theme(name):
    return THEMES.get(name, THEMES[DEFAULT_THEME])


def next_theme(name):
    names = theme_names()
    idx = names.index(name) if name in names else 0
    return names[(idx + 1) % len(names)]


def hex_to_rgb(hex_color: str):
    h = hex_color.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def hex_to_ansi256(hex_color: str) -> str:
    """Hex -> ANSI 256-color escape (SolarSync's conversion)."""
    r, g, b = hex_to_rgb(hex_color)
    ansi = 16 + (36 * round(r / 255 * 5)) + (6 * round(g / 255 * 5)) + round(b / 255 * 5)
    return f"\033[38;5;{ansi}m"


def hex_to_hue(hex_color: str, bri: int = 200):
    """Hex -> Philips Hue (hue 0-65535, sat 0-254, bri 0-254)."""
    r, g, b = (c / 255 for c in hex_to_rgb(hex_color))
    h, s, _v = colorsys.rgb_to_hsv(r, g, b)
    return {"hue": int(h * 65535), "sat": int(s * 254), "bri": max(1, min(254, bri))}


class TermColors:
    """256-color terminal palette for a theme (Ultrareader's Colors)."""

    CR = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"

    # Ultrareader's non-256 fallback map, kept intact.
    _FALLBACK = {
        15: 97, 17: 34, 18: 34, 19: 34, 20: 34, 22: 32, 23: 34, 24: 34, 27: 34,
        28: 32, 29: 36, 30: 36, 33: 36, 34: 32, 35: 36, 36: 36, 39: 36, 40: 32,
        41: 36, 42: 36, 45: 36, 46: 92, 47: 36, 51: 96, 52: 31, 53: 35, 54: 35,
        55: 35, 57: 35, 60: 35, 64: 32, 66: 35, 70: 32, 72: 35, 76: 32, 82: 92,
        87: 96, 88: 31, 91: 35, 93: 35, 97: 35, 98: 35, 99: 35, 104: 35, 110: 35,
        118: 92, 123: 96, 124: 31, 129: 35, 130: 33, 131: 95, 136: 33, 142: 33,
        146: 35, 148: 33, 152: 96, 154: 92, 159: 96, 160: 91, 161: 95, 166: 33,
        167: 95, 168: 95, 170: 33, 172: 33, 173: 95, 175: 95, 176: 33, 178: 33,
        179: 95, 182: 95, 184: 33, 185: 95, 189: 95, 190: 33, 195: 96, 196: 91,
        198: 95, 201: 95, 202: 91, 203: 95, 207: 95, 208: 93, 209: 95, 211: 95,
        214: 93, 215: 95, 217: 95, 218: 95, 220: 93, 221: 95, 226: 93, 227: 95,
        230: 97, 231: 97, 232: 30, 233: 30, 234: 30, 235: 30, 236: 30, 237: 30,
        239: 37, 241: 37, 243: 37, 245: 37, 255: 97,
    }

    def __init__(self, theme_name: str, force_256: bool = None):
        import os
        self.theme_name = theme_name if theme_name in THEMES else DEFAULT_THEME
        self.t = THEMES[self.theme_name]
        if force_256 is None:
            term = os.environ.get("TERM", "")
            self.has_256 = term.endswith("256color") or "256" in os.environ.get("COLORTERM", "")
        else:
            self.has_256 = force_256

    def c(self, code: int) -> str:
        if self.has_256:
            return f"\033[38;5;{code}m"
        return f"\033[{self._FALLBACK.get(code, 37)}m"

    def hex(self, key: str) -> str:
        """Theme hex color (primary/accent1/…) as an ANSI escape."""
        if self.has_256:
            return hex_to_ansi256(self.t[key])
        return self.c(self.t["active"] if key == "primary" else self.t["header"])

    def border(self) -> str:
        return self.c(self.t["border"])

    def header(self) -> str:
        return self.c(self.t["header"])

    def active(self) -> str:
        return self.c(self.t["active"])

    def sel_bg(self) -> str:
        return f"\033[48;5;{self.t['sel_bg']}m" if self.has_256 else "\033[7m"

    def ramp(self, step: int, total: int) -> str:
        ramp = self.t["ramp"]
        if total <= 1:
            return self.c(ramp[0])
        idx = min(int((step / total) * (len(ramp) - 1)), len(ramp) - 1)
        return self.c(ramp[idx])
