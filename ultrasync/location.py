"""Location resolution (SolarSync): IP geolocation with config fallback."""
import json

from . import net

IP_API_URL = ("http://ip-api.com/json/?fields=status,message,country,"
              "countryCode,region,regionName,city,zip,lat,lon,timezone")

DEFAULT_LOCATION = {
    "latitude": 40.7128,
    "longitude": -74.0060,
    "city": "New York",
    "country": "United States",
    "timezone": "America/New_York",
}


def resolve_location(cfg, cache) -> dict:
    """Return {latitude, longitude, city, country, timezone}."""
    if cfg.get("location", "auto_ip", default=True):
        cached = cache.get_fresh("ip_location", max_age=3600)
        data = json.loads(cached) if cached else None
        if data is None:
            data = net.fetch_json(IP_API_URL)
            if data and data.get("status") == "success":
                cache.set("ip_location", json.dumps(data))
            else:
                data = None
        if data:
            return {
                "latitude": data.get("lat"),
                "longitude": data.get("lon"),
                "city": data.get("city"),
                "country": data.get("country"),
                "timezone": data.get("timezone"),
            }
    loc = cfg.get("location", default={}) or {}
    return {
        "latitude": loc.get("latitude") or DEFAULT_LOCATION["latitude"],
        "longitude": loc.get("longitude") or DEFAULT_LOCATION["longitude"],
        "city": loc.get("city") or DEFAULT_LOCATION["city"],
        "country": loc.get("country") or DEFAULT_LOCATION["country"],
        "timezone": loc.get("timezone") or DEFAULT_LOCATION["timezone"],
    }
