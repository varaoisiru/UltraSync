"""Space module — sun/moon, planets, ISS.

SolarSync took sun/moon times from Open-Meteo and used placeholder
planet data. UltraSync keeps the Open-Meteo path but computes real
values locally as well:
- Moon phase from the synodic cycle with true illumination geometry.
- Sunrise/sunset via the NOAA solar algorithm (offline-capable).
- Planet positions via JPL approximate Keplerian elements, converted
  to topocentric altitude/azimuth for the observer.
- ISS live position from the free wheretheiss.at API (no key), with
  SolarSync's general pass guidance as the offline fallback.
"""
import json
import math
from datetime import datetime, timezone
from typing import Dict, List, Optional

from . import net

SYNODIC_MONTH = 29.530588853
KNOWN_NEW_MOON = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)  # known new moon

PHASE_NAMES = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
               "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
PHASE_ICONS = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]


# -- moon -----------------------------------------------------------------
def moon_phase(when: datetime = None) -> float:
    """Lunar phase as a fraction 0..1 (0 = new, 0.5 = full)."""
    when = when or datetime.now(timezone.utc)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    days = (when - KNOWN_NEW_MOON).total_seconds() / 86400.0
    return (days % SYNODIC_MONTH) / SYNODIC_MONTH


def moon_illumination(phase: float) -> float:
    """Illuminated fraction of the disc (geometric, 0..1)."""
    return (1 - math.cos(2 * math.pi * phase)) / 2


def _phase_index(phase: float) -> int:
    # Bins are centered on the cardinal points (0=new, 0.25=first quarter,
    # 0.5=full, 0.75=last quarter) — SolarSync's icon boundaries.
    return int((phase + 0.0625) * 8) % 8


def moon_phase_name(phase: float) -> str:
    return PHASE_NAMES[_phase_index(phase)]


def moon_phase_icon(phase: float) -> str:
    return PHASE_ICONS[_phase_index(phase)]


# -- sun times (NOAA algorithm) --------------------------------------------
def _julian_day(when: datetime) -> float:
    return when.timestamp() / 86400.0 + 2440587.5


def sun_times(date: datetime, lat: float, lon: float):
    """(sunrise_utc, sunset_utc) datetimes via the NOAA algorithm.

    Accurate to a couple of minutes for most locations/dates.
    Returns (None, None) for polar day/night.
    """
    jd = _julian_day(date.replace(hour=12, minute=0, second=0))
    t = (jd - 2451545.0) / 36525.0
    geom_mean_long = (280.46646 + t * (36000.76983 + 0.0003032 * t)) % 360
    geom_mean_anom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
    ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    anom_r = math.radians(geom_mean_anom)
    sun_eq_ctr = (math.sin(anom_r) * (1.914602 - t * (0.004817 + 0.000014 * t))
                  + math.sin(2 * anom_r) * (0.019993 - 0.000101 * t)
                  + math.sin(3 * anom_r) * 0.000289)
    sun_true_long = geom_mean_long + sun_eq_ctr
    omega = 125.04 - 1934.136 * t
    sun_app_long = sun_true_long - 0.00569 - 0.00478 * math.sin(math.radians(omega))
    mean_obliq = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
    obliq_corr = mean_obliq + 0.00256 * math.cos(math.radians(omega))
    decl = math.degrees(math.asin(math.sin(math.radians(obliq_corr))
                                  * math.sin(math.radians(sun_app_long))))
    var_y = math.tan(math.radians(obliq_corr) / 2) ** 2
    eq_time = 4 * math.degrees(
        var_y * math.sin(2 * math.radians(geom_mean_long))
        - 2 * ecc * math.sin(anom_r)
        + 4 * ecc * var_y * math.sin(anom_r) * math.cos(2 * math.radians(geom_mean_long))
        - 0.5 * var_y ** 2 * math.sin(4 * math.radians(geom_mean_long))
        - 1.25 * ecc ** 2 * math.sin(2 * anom_r))
    lat_r, decl_r = math.radians(lat), math.radians(decl)
    cos_ha = (math.cos(math.radians(90.833)) / (math.cos(lat_r) * math.cos(decl_r))
              - math.tan(lat_r) * math.tan(decl_r))
    if cos_ha > 1 or cos_ha < -1:
        return None, None  # polar day / night
    ha = math.degrees(math.acos(cos_ha))
    sunrise_min = 720 - 4 * (lon + ha) - eq_time
    sunset_min = 720 - 4 * (lon - ha) - eq_time
    base = date.replace(hour=0, minute=0, second=0, microsecond=0)
    from datetime import timedelta
    return base + timedelta(minutes=sunrise_min), base + timedelta(minutes=sunset_min)


# -- planets (JPL approximate elements, valid 1800–2050) --------------------
# (a [AU], e, I [deg], L [deg], ϖ [deg], Ω [deg],
#  ȧ, ė, İ, L̇, ϖ̇, Ω̇ per Julian century)
_ELEMENTS = {
    "Mercury": (0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593,
                0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081),
    "Venus": (0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255,
              0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418),
    "Mars": (1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891,
             0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343),
    "Jupiter": (5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909,
                -0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106),
    "Saturn": (9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448,
               -0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794),
}


def _kepler(m_deg: float, e: float) -> float:
    m = math.radians(m_deg % 360)
    ecc_anom = m
    for _ in range(10):
        ecc_anom -= (ecc_anom - e * math.sin(ecc_anom) - m) / (1 - e * math.cos(ecc_anom))
    return ecc_anom


def planet_positions(when: datetime, lat: float, lon: float) -> List[Dict]:
    """Topocentric altitude/azimuth + visibility for the visible planets."""
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    jd = _julian_day(when)
    t = (jd - 2451545.0) / 36525.0

    def helio(name):
        a, e, inc, L, varpi, node, da, de, dI, dL, dvarpi, dnode = _ELEMENTS[name]
        a += da * t; e += de * t; inc += dI * t; L += dL * t
        varpi += dvarpi * t; node += dnode * t
        m = L - varpi
        w = varpi - node
        E = _kepler(m, e)
        xp = a * (math.cos(E) - e)
        yp = a * math.sqrt(1 - e * e) * math.sin(E)
        cosE, sinE = math.cos(math.radians(w)), math.sin(math.radians(w))
        cosI, sinI = math.cos(math.radians(inc)), math.sin(math.radians(inc))
        cosN, sinN = math.cos(math.radians(node)), math.sin(math.radians(node))
        x = (cosE * cosN - sinE * sinN * cosI) * xp + (-sinE * cosN - cosE * sinN * cosI) * yp
        y = (cosE * sinN + sinE * cosN * cosI) * xp + (-sinE * sinN + cosE * cosN * cosI) * yp
        z = (sinE * sinI) * xp + (cosE * sinI) * yp
        return x, y, z

    # Earth's own heliocentric position from its JPL approximate elements —
    # geocentric planet position = planet_helio - earth_helio.
    _ELEMENTS["Earth"] = (1.00000261, 0.01671123, -0.00001531, 100.46457166,
                          102.93768193, 0.0,
                          0.00000562, -0.00004392, -0.01294668, 35999.37244981,
                          0.32327364, 0.0)
    earth = helio("Earth")
    del _ELEMENTS["Earth"]

    # GMST for alt/az
    gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)) % 360
    lst = (gmst + lon) % 360

    results = []
    for name in _ELEMENTS:
        hx, hy, hz = helio(name)
        gx, gy, gz = hx - earth[0], hy - earth[1], hz - earth[2]
        ecl = math.degrees(math.atan2(gy, gx)) % 360
        ecl_lat = math.degrees(math.atan2(gz, math.hypot(gx, gy)))
        eps = math.radians(23.439281)
        ra = math.degrees(math.atan2(
            math.sin(math.radians(ecl)) * math.cos(eps) - math.tan(math.radians(ecl_lat)) * math.sin(eps),
            math.cos(math.radians(ecl)))) % 360
        dec = math.degrees(math.asin(
            math.sin(math.radians(ecl_lat)) * math.cos(eps)
            + math.cos(math.radians(ecl_lat)) * math.sin(eps) * math.sin(math.radians(ecl))))
        ha = math.radians((lst - ra + 180) % 360 - 180)
        dec_r, lat_r = math.radians(dec), math.radians(lat)
        alt = math.degrees(math.asin(
            math.sin(dec_r) * math.sin(lat_r) + math.cos(dec_r) * math.cos(lat_r) * math.cos(ha)))
        az = math.degrees(math.atan2(
            math.sin(ha), math.cos(ha) * math.sin(lat_r) - math.tan(dec_r) * math.cos(lat_r))) + 180
        results.append({
            "name": name,
            "altitude": round(alt, 1),
            "azimuth": round(az % 360, 1),
            "visible": alt > 0,
        })
    return results


# -- ISS ---------------------------------------------------------------------
ISS_URL = "https://api.wheretheiss.at/v1/satellites/25544"
ISS_FALLBACK = {
    "time": "Multiple passes daily",
    "duration": "2-5 min",
    "max_elevation": "Varies",
    "brightness": "-2.5 to -4.0 mag",
}


def fetch_iss(cache) -> Optional[Dict]:
    cached = cache.get_fresh("iss", max_age=30)
    if cached:
        return json.loads(cached)
    data = net.fetch_json(ISS_URL, timeout=6)
    if data and "latitude" in data:
        out = {
            "latitude": round(data["latitude"], 2),
            "longitude": round(data["longitude"], 2),
            "altitude_km": round(data.get("altitude", 0), 1),
            "velocity_kmh": round(data.get("velocity", 0)),
            "visibility": data.get("visibility"),
            "live": True,
        }
        cache.set("iss", json.dumps(out))
        return out
    stale = cache.get_entry("iss")
    if stale:
        out = json.loads(stale[0])
        out["live"] = False
        return out
    return None


# -- assembled space payload ---------------------------------------------------
def fetch_space(cfg, cache, location: Dict) -> Dict:
    """Open-Meteo sun/moon times, with local computation as the backbone."""
    lat = location.get("latitude", 40.7128)
    lon = location.get("longitude", -74.0060)
    now = datetime.now(timezone.utc)

    phase = moon_phase(now)
    space: Dict = {
        "sun_times": {},
        "moon_data": {
            "phase": round(phase, 4),
            "illumination": round(moon_illumination(phase) * 100, 1),
            "name": moon_phase_name(phase),
            "icon": moon_phase_icon(phase),
        },
        "planets": planet_positions(now, lat, lon),
        "iss": fetch_iss(cache),
        "iss_passes": ISS_FALLBACK,
    }

    rise, set_ = sun_times(now, lat, lon)
    if rise:
        space["sun_times"]["sunrise_utc"] = rise.isoformat()
        space["sun_times"]["sunset_utc"] = set_.isoformat()

    # Open-Meteo supplies moonrise/moonset + local sun times when online.
    cached = cache.get_fresh("space_times", max_age=900)
    payload = json.loads(cached) if cached else None
    if payload is None:
        url = (f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
               "&daily=sunrise,sunset,moonrise,moonset&timezone=auto&forecast_days=1")
        payload = net.fetch_json(url)
        if payload:
            cache.set("space_times", json.dumps(payload))
    if payload and "daily" in payload:
        daily = payload["daily"]
        for key in ("sunrise", "sunset", "moonrise", "moonset"):
            vals = daily.get(key) or [None]
            if vals and vals[0]:
                space["sun_times"][key] = vals[0]
    return space
