"""Daily briefing card (UltraSync 2.0).

Assembles the day's headline numbers — weather, geomagnetics, top
story — from the same DataService payloads the GUI shows, and renders
them as a shareable 1200x630 PNG in the active theme's colors.

Assembly is pure and always available (GET /api/briefing). Rendering
needs Pillow; without it render_briefing_png() returns None and the
API degrades to the JSON form instead of failing.
"""
import os
from datetime import datetime
from typing import Dict, Optional

from . import __version__
from .themes import hex_to_rgb

CARD_W, CARD_H = 1200, 630

_FONT_DIRS = (
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/dejavu",
    "/System/Library/Fonts/Supplemental",
    "C:/Windows/Fonts",
)


def _fmt(value, digits=0):
    if value is None:
        return "—"
    try:
        return f"{float(value):.{digits}f}"
    except (TypeError, ValueError):
        return str(value)


def assemble_briefing(weather: Dict, solar: Dict, news: Dict,
                      now: datetime = None) -> Dict:
    """The card's data, from DataService payloads. Missing panels
    degrade to placeholder lines rather than raising."""
    now = now or datetime.now()
    weather = weather or {}
    solar = solar or {}
    news = news or {}

    cur = weather.get("current") or {}
    daily = weather.get("daily") or []
    today = daily[0] if daily else {}
    unit = weather.get("unit_symbol", "°C")
    if weather.get("ok") and cur.get("description"):
        weather_summary = (f"{cur['description']} · {_fmt(cur.get('temperature'))}{unit} "
                           f"(feels {_fmt(cur.get('feels_like'))}{unit})")
        temp_range = (f"H {_fmt(today.get('max'))}° / L {_fmt(today.get('min'))}°"
                      if today else "")
    else:
        weather_summary, temp_range = "Weather unavailable", ""

    geo = solar.get("geomagnetic") or {}
    kp = geo.get("kp_index")
    if kp is not None:
        solar_summary = (f"Kp {_fmt(kp, 1)} — {geo.get('label', '')} · "
                         f"sunspots {_fmt(solar.get('sunspot_number'))} · "
                         f"flux {_fmt(solar.get('solar_flux'))} · "
                         f"aurora {geo.get('aurora_probability', '—')}%")
    else:
        solar_summary = "Solar data unavailable"

    articles = news.get("articles") or []
    top = articles[0] if articles else {}
    return {
        "date": now.strftime("%A, %B %d, %Y"),
        "location": (weather.get("location") or {}).get("city") or "",
        "weather_summary": weather_summary,
        "temp_range": temp_range,
        "kp_index": kp,
        "kp_label": geo.get("label"),
        "solar_summary": solar_summary,
        "headline": top.get("display_title") or "No headlines yet — refresh the feeds",
        "headline_source": top.get("source", ""),
        "unread": news.get("total_unread", 0),
        "version": __version__,
    }


def _load_font(size: int, bold: bool = False):
    from PIL import ImageFont
    names = ("DejaVuSans-Bold.ttf", "Arial Bold.ttf", "arialbd.ttf") if bold \
        else ("DejaVuSans.ttf", "Arial.ttf", "arial.ttf")
    for directory in _FONT_DIRS:
        for name in names:
            path = os.path.join(directory, name)
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1: bitmap default font
        return ImageFont.load_default()


def _wrap(draw, text: str, font, max_width: int, max_lines: int = 3):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
            if len(lines) == max_lines:
                break
    if line and len(lines) < max_lines:
        lines.append(line)
    if len(lines) == max_lines and len(" ".join(lines)) < len(text):
        lines[-1] = lines[-1].rstrip(" .") + "…"
    return lines


def render_briefing_png(data: Dict, theme: Dict) -> Optional[bytes]:
    """Render the card. Returns None when Pillow is not installed."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None

    bg = hex_to_rgb(theme.get("bg", "#0a0a0a"))
    primary = hex_to_rgb(theme.get("primary", "#00ff41"))
    accent1 = hex_to_rgb(theme.get("accent1", "#ff6600"))
    accent2 = hex_to_rgb(theme.get("accent2", "#ffaa00"))
    accent3 = hex_to_rgb(theme.get("accent3", "#ff3300"))
    soft = tuple(min(255, c + 90) for c in bg)

    img = Image.new("RGB", (CARD_W, CARD_H), bg)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, CARD_W, 14], fill=accent1)
    d.rectangle([0, CARD_H - 14, CARD_W, CARD_H], fill=accent1)

    f_kicker = _load_font(30)
    f_title = _load_font(60, bold=True)
    f_body = _load_font(38)
    f_label = _load_font(26)
    f_head = _load_font(40, bold=True)
    width = CARD_W - 120

    d.text((60, 40), f"ULTRASYNC {data['version']} — DAILY BRIEFING", font=f_kicker, fill=accent2)
    d.text((60, 84), data["date"], font=f_title, fill=primary)
    if data["location"]:
        d.text((60, 158), data["location"], font=_load_font(34), fill=accent2)
    d.line([60, 206, CARD_W - 60, 206], fill=soft, width=2)

    label = "WEATHER" + (f"  ·  {data['temp_range']}" if data["temp_range"] else "")
    d.text((60, 224), label, font=f_label, fill=accent2)
    y = 262
    for line in _wrap(d, data["weather_summary"], f_body, width, max_lines=1):
        d.text((60, y), line, font=f_body, fill=primary)

    kp = data.get("kp_index")
    solar_fill = accent3 if (kp is not None and float(kp) >= 5) else primary
    d.text((60, 330), "SOLAR", font=f_label, fill=accent2)
    for line in _wrap(d, data["solar_summary"], f_body, width, max_lines=1):
        d.text((60, 368), line, font=f_body, fill=solar_fill)

    d.text((60, 442), "TOP STORY" + (f"  ·  {data['headline_source']}" if data["headline_source"] else ""),
           font=f_label, fill=accent2)
    y = 478
    for line in _wrap(d, data["headline"], f_head, width, max_lines=2):
        d.text((60, y), line, font=f_head, fill=primary)
        y += 48
    return _to_bytes(img)


def _to_bytes(img) -> bytes:
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()
