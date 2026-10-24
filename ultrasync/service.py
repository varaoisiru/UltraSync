"""Shared data layer for UltraSync.

One DataService instance feeds every surface — the FastAPI JSON API
(and therefore the web GUI), the terminal UI, and the HTML export.
Each getter follows the same contract: fresh cache → live fetch →
stale cache (flagged) → structured empty state. Nothing raises.
"""
import threading
import time
from datetime import datetime
from typing import Dict, Optional

from . import location as loc_mod
from . import news as news_mod
from . import solar as solar_mod
from . import space as space_mod
from . import weather as wx_mod
from .cache import Cache
from .config import Config


class DataService:
    def __init__(self, cfg: Config = None, cache: Cache = None):
        self.cfg = cfg or Config()
        self.cache = cache or Cache()
        self._location: Optional[Dict] = None
        self._loc_lock = threading.Lock()

    # -- location ---------------------------------------------------------
    def location(self) -> Dict:
        with self._loc_lock:
            if self._location is None:
                self._location = loc_mod.resolve_location(self.cfg, self.cache)
            return self._location

    # -- freshness helper --------------------------------------------------
    def _meta(self, key: str, max_age: int = 900) -> Dict:
        entry = self.cache.get_entry(key)
        if not entry:
            return {"stale": True, "age_seconds": None, "fetched_at": None}
        age = time.time() - entry[1]
        return {"stale": age >= max_age, "age_seconds": int(age),
                "fetched_at": entry[1]}

    # -- news ---------------------------------------------------------------
    def refresh_news(self) -> int:
        return news_mod.fetch_all_feeds(self.cfg, self.cache)

    def get_news(self, source: str = None, search: str = "", limit: int = 60) -> Dict:
        articles = self.cache.load_articles(search=search, source=source, limit=limit)
        for a in articles:
            title = a["title"]
            prefix = f"[{a['source']}] "
            a["display_title"] = title[len(prefix):] if title.startswith(prefix) else title
        sources = sorted({name for feeds in (self.cfg.get("feeds", default={}) or {}).values()
                          for name, _url in feeds})
        return {
            "articles": articles,
            "unread": self.cache.count_unread(source),
            "total_unread": self.cache.count_unread(),
            "sources": sources,
            "count": len(articles),
        }

    def mark_read(self, link: str):
        self.cache.mark_viewed(link)

    def mark_all_read(self, source: str = None):
        self.cache.mark_all_viewed(source)

    def get_article(self, link: str) -> Dict:
        paragraphs = news_mod.fetch_article_paragraphs(link)
        self.cache.mark_viewed(link)
        return {"link": link, "paragraphs": paragraphs}

    # -- weather --------------------------------------------------------------
    def get_weather(self) -> Dict:
        loc = self.location()
        units = self.cfg.get("preferences", "units", default="metric")
        tf = self.cfg.get("preferences", "time_format", default="24h")
        raw = wx_mod.fetch_weather(self.cfg, self.cache, loc)
        meta = self._meta("weather")
        if not raw:
            return {"ok": False, "error": "weather unavailable (offline, no cache)",
                    "location": loc, **meta}

        current = raw.get("current", {}) or {}
        out_current = {
            "temperature": wx_mod.convert_temp(current.get("temperature_2m"), units),
            "feels_like": wx_mod.convert_temp(current.get("apparent_temperature"), units),
            "humidity": current.get("relative_humidity_2m"),
            "precipitation": current.get("precipitation"),
            "weather_code": current.get("weather_code"),
            "description": wx_mod.weather_desc(current.get("weather_code")),
            "icon": wx_mod.weather_icon(current.get("weather_code")),
            "cloud_cover": current.get("cloud_cover"),
            "wind_speed": current.get("wind_speed_10m"),
            "wind_direction_deg": current.get("wind_direction_10m"),
            "wind_direction": wx_mod.wind_direction(current.get("wind_direction_10m", 0)),
            "is_day": current.get("is_day"),
        }

        hourly_raw = raw.get("hourly", {}) or {}
        times = hourly_raw.get("time", [])
        temps = hourly_raw.get("temperature_2m", [])
        codes = hourly_raw.get("weather_code", [])
        now_hour = datetime.now().strftime("%Y-%m-%dT%H:00")
        start = 0
        for i, t in enumerate(times):
            if t >= now_hour:
                start = i
                break
        hourly = [
            {"time": t, "label": wx_mod.format_time(t, tf),
             "temperature": wx_mod.convert_temp(temp, units),
             "weather_code": code, "icon": wx_mod.weather_icon(code)}
            for t, temp, code in zip(times[start:start + 24],
                                     temps[start:start + 24],
                                     codes[start:start + 24])
        ]

        daily_raw = raw.get("daily", {}) or {}
        daily = []
        for i, day in enumerate(daily_raw.get("time", [])[:7]):
            try:
                label = datetime.fromisoformat(day).strftime("%a")
            except Exception:
                label = day[:3]
            daily.append({
                "date": day, "label": label,
                "max": wx_mod.convert_temp(daily_raw.get("temperature_2m_max", [None] * 7)[i], units),
                "min": wx_mod.convert_temp(daily_raw.get("temperature_2m_min", [None] * 7)[i], units),
                "weather_code": daily_raw.get("weather_code", [None] * 7)[i],
                "icon": wx_mod.weather_icon(daily_raw.get("weather_code", [0] * 7)[i]),
                "precip_probability": daily_raw.get("precipitation_probability_max", [None] * 7)[i],
                "sunrise": daily_raw.get("sunrise", [None] * 7)[i],
                "sunset": daily_raw.get("sunset", [None] * 7)[i],
            })

        return {"ok": True, "location": loc, "units": units,
                "unit_symbol": "°F" if units == "imperial" else "°C",
                "current": out_current, "hourly": hourly, "daily": daily, **meta}

    # -- solar ------------------------------------------------------------
    def get_solar(self) -> Dict:
        raw = solar_mod.fetch_solar(self.cache)
        meta = self._meta("solar")
        ok = raw.get("sunspot_number") is not None or raw.get("geomagnetic") is not None
        return {"ok": ok, **raw, **meta}

    # -- space --------------------------------------------------------------
    def get_space(self) -> Dict:
        loc = self.location()
        raw = space_mod.fetch_space(self.cfg, self.cache, loc)
        return {"ok": True, "location": loc, **raw}

    # -- status ------------------------------------------------------------
    def status(self) -> Dict:
        from . import __version__
        return {
            "ok": True,
            "version": __version__,
            "theme": self.cfg.get("preferences", "theme", default="cyberfire"),
            "location": self.location(),
            "hue_configured": self.cfg.hue_configured(),
            "unread": self.cache.count_unread(),
            "weather": self._meta("weather"),
            "solar": self._meta("solar"),
        }
