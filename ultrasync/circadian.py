"""Circadian solar sync (UltraSync 2.0).

A second Hue sync engine next to condition sync: instead of mapping
weather/Kp to a fixed color, it tracks the sun. Color temperature and
brightness follow the sun's arc between sunrise and sunset — warm and
dim at the horizons (2200K), cool and bright at solar noon (6500K) —
and settle to a dim warm ember overnight.

Pure functions over datetimes, fed by the space module's NOAA sunrise/
sunset computation. No credentials, no I/O: the caller (api.py) takes
the payload dict and pushes it through the existing HueClient.
"""
import math
from datetime import datetime, timezone
from typing import Dict, Optional

HORIZON_KELVIN = 2200   # sunrise / sunset warmth
NOON_KELVIN = 6500      # full daylight at solar noon
NIGHT_KELVIN = 2200     # overnight ember
NIGHT_BRI = 15
DAWN_BRI = 30           # brightness right at sunrise/sunset
MAX_BRI = 254
TRANSITION = 10         # 1 s glide, same as condition sync


def kelvin_to_mirek(kelvin: float) -> int:
    """Kelvin -> Hue mirek (reciprocal megakelvin), clamped to 153..500."""
    if kelvin <= 0:
        return 500
    return max(153, min(500, round(1_000_000 / kelvin)))


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def circadian_state(now: datetime, sunrise: datetime,
                    sunset: datetime) -> Optional[Dict]:
    """Light state for `now` given the day's sunrise/sunset (UTC-aware).

    Returns None when the sun times are unusable (missing, or a polar
    day/night where sunset <= sunrise). Day shape: the sun's elevation
    is modelled as sin(pi * day_fraction), so temperature and
    brightness peak together at solar noon.
    """
    if sunrise is None or sunset is None:
        return None
    now, sunrise, sunset = _aware(now), _aware(sunrise), _aware(sunset)
    if sunset <= sunrise:
        return None

    if now < sunrise or now >= sunset:
        return {
            "phase": "night",
            "day_fraction": None,
            "kelvin": NIGHT_KELVIN,
            "payload": {"on": True, "bri": NIGHT_BRI,
                        "ct": kelvin_to_mirek(NIGHT_KELVIN),
                        "transitiontime": TRANSITION},
        }

    fraction = (now - sunrise).total_seconds() / (sunset - sunrise).total_seconds()
    elevation = math.sin(math.pi * fraction)          # 0 at horizons, 1 at noon
    kelvin = HORIZON_KELVIN + (NOON_KELVIN - HORIZON_KELVIN) * elevation ** 0.75
    bri = round(DAWN_BRI + (MAX_BRI - DAWN_BRI) * elevation)
    return {
        "phase": "day",
        "day_fraction": round(fraction, 4),
        "kelvin": round(kelvin),
        "payload": {"on": True, "bri": max(1, min(MAX_BRI, bri)),
                    "ct": kelvin_to_mirek(kelvin),
                    "transitiontime": TRANSITION},
    }


def _parse_iso(value) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def circadian_from_space(space: Dict, now: datetime = None) -> Optional[Dict]:
    """circadian_state() from a DataService.get_space() payload."""
    sun = (space or {}).get("sun_times") or {}
    sunrise = _parse_iso(sun.get("sunrise_utc"))
    sunset = _parse_iso(sun.get("sunset_utc"))
    return circadian_state(now or datetime.now(timezone.utc), sunrise, sunset)
