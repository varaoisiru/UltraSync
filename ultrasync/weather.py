"""Weather module — SolarSync's Open-Meteo integration.

Fetches current conditions, hourly and 7-day daily forecasts through
the unified cache. Formatting helpers (units, wind compass, WMO codes)
are merged from both parents: SolarSync's icon set + Ultrareader's
text descriptions.
"""
import json
from datetime import datetime
from typing import Dict, Optional

from . import net

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

# SolarSync's icon set
WMO_ICONS = {
    0: "☀", 1: "🌤", 2: "⛅", 3: "☁", 45: "🌫", 48: "🌫",
    51: "🌧", 53: "🌧", 55: "🌧", 61: "🌧", 63: "🌧", 65: "⛈",
    71: "❄", 73: "❄", 75: "❄", 77: "❄", 80: "🌧", 81: "🌧", 82: "⛈",
    85: "❄", 86: "❄", 95: "⛈", 96: "⛈", 99: "⛈",
}

# Ultrareader's text descriptions
WMO_DESC = {
    0: "Clear", 1: "Mainly Clear", 2: "Partly Cloudy", 3: "Overcast",
    45: "Foggy", 48: "Icy Fog",
    51: "Lt Drizzle", 53: "Drizzle", 55: "Hvy Drizzle",
    61: "Lt Rain", 63: "Rain", 65: "Hvy Rain",
    71: "Lt Snow", 73: "Snow", 75: "Hvy Snow", 77: "Snow Grains",
    80: "Showers", 81: "Hvy Showers", 82: "Violent Showers",
    85: "Snow Showers", 86: "Hvy Snow Showers",
    95: "T-Storm", 96: "T-Storm+Hail", 99: "T-Storm+Hail",
}


def weather_icon(code) -> str:
    try:
        return WMO_ICONS.get(int(code), "?")
    except (TypeError, ValueError):
        return "?"


def weather_desc(code) -> str:
    try:
        return WMO_DESC.get(int(code), "Unknown")
    except (TypeError, ValueError):
        return "Unknown"


def wind_direction(degrees) -> str:
    directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                  "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    try:
        return directions[round(float(degrees) / 22.5) % 16]
    except (TypeError, ValueError):
        return "?"


def format_temperature(temp_c, units: str) -> str:
    if temp_c is None:
        return "--"
    try:
        temp_c = float(temp_c)
    except (TypeError, ValueError):
        return "--"
    if units == "imperial":
        return f"{temp_c * 9 / 5 + 32:.0f}°F"
    return f"{temp_c:.0f}°C"


def convert_temp(temp_c, units: str):
    """Numeric temperature in the active unit system (for charts)."""
    if temp_c is None:
        return None
    return temp_c * 9 / 5 + 32 if units == "imperial" else float(temp_c)


def format_time(iso_str: str, time_format: str = "24h") -> str:
    if not iso_str:
        return "--:--"
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        if time_format == "12h":
            return dt.strftime("%I:%M %p")
        return dt.strftime("%H:%M")
    except Exception:
        return iso_str


def fetch_weather(cfg, cache, location: Dict) -> Optional[Dict]:
    """Raw Open-Meteo payload via the unified cache (15-min freshness)."""
    cached = cache.get_fresh("weather", max_age=900)
    if cached:
        return json.loads(cached)

    lat = location.get("latitude", 40.7128)
    lon = location.get("longitude", -74.0060)
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": ("temperature_2m,relative_humidity_2m,apparent_temperature,"
                    "precipitation,weather_code,cloud_cover,wind_speed_10m,"
                    "wind_direction_10m,is_day"),
        "hourly": ("temperature_2m,relative_humidity_2m,"
                   "precipitation_probability,weather_code,wind_speed_10m,"
                   "uv_index"),
        "daily": ("weather_code,temperature_2m_max,temperature_2m_min,"
                  "sunrise,sunset,uv_index_max,precipitation_sum,"
                  "precipitation_probability_max"),
        "timezone": "auto",
        "forecast_days": 7,
    }
    query = "&".join(f"{k}={v}" for k, v in params.items())
    data = net.fetch_json(f"{FORECAST_URL}?{query}")
    if data:
        cache.set("weather", json.dumps(data))
        return data
    stale = cache.get_entry("weather")
    return json.loads(stale[0]) if stale else None
