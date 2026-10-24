"""Solar activity module — SolarSync's NOAA SWPC integration.

Sources (all free, no key): observed solar-cycle indices, real-time
solar wind (RTSW wind + magnetometer), 1-minute planetary K index, and
the NOAA planetary K forecast table. Solar wind speed/density come from
the RTSW *wind* product (SolarSync read them from the magnetometer
product, which carries field data, not plasma speed).
"""
import json
from typing import Dict, Optional

from . import net

INDICES_URL = "https://services.swpc.noaa.gov/json/solar-cycle/observed-solar-cycle-indices.json"
WIND_URL = "https://services.swpc.noaa.gov/json/rtsw/rtsw_wind_1m.json"
MAG_URL = "https://services.swpc.noaa.gov/json/rtsw/rtsw_mag_1m.json"
KP_URL = "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json"
REGIONS_URL = "https://services.swpc.noaa.gov/json/solar-region/solar-region-summary.json"
FORECAST_URL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"

EMPTY = {
    "sunspot_number": None,
    "solar_flux": None,
    "solar_wind": None,
    "geomagnetic": None,
    "active_regions": None,
    "alerts": [],
    "forecast": {},
}


def aurora_probability(kp) -> int:
    """SolarSync's rule of thumb: Kp scaled to a percentage."""
    try:
        return min(100, int(float(kp) * 11))
    except (TypeError, ValueError):
        return 0


def kp_label(kp) -> str:
    try:
        kp = float(kp)
    except (TypeError, ValueError):
        return "Unknown"
    if kp < 4:
        return "Quiet"
    if kp < 5:
        return "Unsettled"
    if kp < 6:
        return "G1 Minor storm"
    if kp < 7:
        return "G2 Moderate storm"
    if kp < 8:
        return "G3 Strong storm"
    if kp < 9:
        return "G4 Severe storm"
    return "G5 Extreme storm"


def fetch_solar(cache) -> Dict:
    """Assemble the solar dataset, per-feed cache fallback."""
    cached = cache.get_fresh("solar", max_age=900)
    if cached:
        return json.loads(cached)

    solar = dict(EMPTY)
    got_any = False

    indices = net.fetch_json(INDICES_URL)
    if indices:
        # Recent months carry -1 sentinels for smoothed values; walk back
        # to the newest row with real data. Keys are the live SWPC schema
        # (ssn / observed_swpc_ssn / f10.7).
        def _valid(row, *keys):
            for key in keys:
                v = row.get(key)
                if isinstance(v, (int, float)) and v >= 0:
                    return v
            return None
        for row in reversed(indices):
            if solar["sunspot_number"] is None:
                solar["sunspot_number"] = _valid(row, "smoothed_ssn", "observed_swpc_ssn", "ssn")
            if solar["solar_flux"] is None:
                solar["solar_flux"] = _valid(row, "smoothed_f10.7", "f10.7")
            if solar["sunspot_number"] is not None and solar["solar_flux"] is not None:
                break
        got_any = True

    wind = net.fetch_json(WIND_URL)
    if wind:
        latest = wind[-1]
        solar["solar_wind"] = {
            "speed": latest.get("proton_speed"),
            "density": latest.get("proton_density"),
            "temperature": latest.get("proton_temperature"),
        }
        got_any = True

    mag = net.fetch_json(MAG_URL)
    if mag and solar["solar_wind"] is not None:
        latest = mag[-1]
        solar["solar_wind"]["bz"] = latest.get("bz_gsm")
        solar["solar_wind"]["bt"] = latest.get("bt")

    geo = net.fetch_json(KP_URL)
    if geo:
        latest = geo[-1]
        kp = latest.get("kp_index", latest.get("k_index", 0))
        solar["geomagnetic"] = {
            "kp_index": kp,
            "a_index": latest.get("a_index", 0),
            "label": kp_label(kp),
            "aurora_probability": aurora_probability(kp),
        }
        got_any = True

    regions = net.fetch_json(REGIONS_URL)
    if regions:
        solar["active_regions"] = regions.get("number_of_cmc_calculated_regions", 0)
        got_any = True

    forecast = net.fetch_json(FORECAST_URL)
    if forecast:
        table = {}
        rows = forecast[1:] if forecast and isinstance(forecast[0], list) else forecast
        for entry in rows:
            if isinstance(entry, dict):
                day = entry.get("time_tag") or entry.get("date") or ""
                kp = entry.get("Kp", entry.get("kp_index"))
                a_idx = entry.get("a_running", entry.get("a_index"))
                if day and kp is not None:
                    table[str(day)[:10]] = {"kp_index": kp, "a_index": a_idx}
            elif isinstance(entry, list) and len(entry) >= 4:
                table[entry[0]] = {"kp_index": entry[2], "a_index": entry[3]}
        if table:
            solar["forecast"] = table
            got_any = True

    if got_any:
        cache.set("solar", json.dumps(solar))
        return solar
    stale = cache.get_entry("solar")
    return json.loads(stale[0]) if stale else solar
