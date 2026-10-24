import json
import os
import sys
import time
from pathlib import Path

# Isolate all state + force offline before any ultrasync module loads.
_TMP = Path(__file__).parent / ".tmp_state"
os.environ["ULTRASYNC_CONFIG_DIR"] = str(_TMP / "config")
os.environ["ULTRASYNC_CACHE_DIR"] = str(_TMP / "cache")
os.environ["ULTRASYNC_NO_NET"] = "1"

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402

from ultrasync.cache import Cache  # noqa: E402
from ultrasync.config import Config  # noqa: E402
from ultrasync.service import DataService  # noqa: E402

WEATHER_RAW = {
    "current": {"temperature_2m": 21.5, "relative_humidity_2m": 40,
                "apparent_temperature": 20.0, "precipitation": 0.0,
                "weather_code": 2, "cloud_cover": 25, "wind_speed_10m": 12.0,
                "wind_direction_10m": 90, "is_day": 1},
    "hourly": {
        "time": [f"2026-10-24T{h:02d}:00" for h in range(24)],
        "temperature_2m": [15.0 + h * 0.5 for h in range(24)],
        "weather_code": [1] * 24,
    },
    "daily": {
        "time": ["2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27",
                 "2026-10-28", "2026-10-29", "2026-10-30"],
        "temperature_2m_max": [26.0] * 7, "temperature_2m_min": [14.0] * 7,
        "weather_code": [0] * 7, "precipitation_probability_max": [10] * 7,
        "sunrise": ["2026-10-24T06:34"] * 7, "sunset": ["2026-10-24T17:37"] * 7,
    },
}

SOLAR_ASSEMBLED = {
    "sunspot_number": 82.0, "solar_flux": 121.5,
    "solar_wind": {"speed": 430.0, "density": 4.2, "temperature": 90000, "bz": -1.5, "bt": 5.0},
    "geomagnetic": {"kp_index": 3, "a_index": 12, "label": "Quiet", "aurora_probability": 33},
    "active_regions": 5, "alerts": [],
    "forecast": {"2026-10-24": {"kp_index": 3, "a_index": 12}},
}


@pytest.fixture()
def cache(tmp_path):
    return Cache(tmp_path / "test.db")


@pytest.fixture()
def cfg(tmp_path):
    return Config(tmp_path / "config.json")


@pytest.fixture()
def service(cache, cfg):
    """DataService seeded with cached payloads (offline by design)."""
    cache.set("weather", json.dumps(WEATHER_RAW))
    cache.set("solar", json.dumps(SOLAR_ASSEMBLED))
    cache.save_articles([
        {"source": "BBC", "title": "[BBC] Seeded Headline One",
         "link": "https://example.com/1", "summary": "First seeded story."},
        {"source": "NASA", "title": "[NASA] Seeded Headline Two",
         "link": "https://example.com/2", "summary": "Second seeded story."},
    ])
    return DataService(cfg, cache)
