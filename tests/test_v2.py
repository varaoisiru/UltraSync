"""UltraSync 2.0 features: circadian sync, briefing card, Aurora Veil."""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from ultrasync.api import create_app
from ultrasync.briefing import assemble_briefing, render_briefing_png
from ultrasync.circadian import circadian_from_space, circadian_state, kelvin_to_mirek
from ultrasync.hue_fx import FX
from ultrasync import themes

UTC = timezone.utc
SUNRISE = datetime(2026, 10, 24, 11, 0, tzinfo=UTC)   # 04:00 MST
SUNSET = datetime(2026, 10, 25, 1, 0, tzinfo=UTC)     # 18:00 MST


def at(hour, minute=0):
    return datetime(2026, 10, 24, hour, minute, tzinfo=UTC)


# -- circadian curve ------------------------------------------------------
def test_mirek_clamps_to_hue_range():
    assert kelvin_to_mirek(6500) == 154
    assert kelvin_to_mirek(2200) == 455
    assert kelvin_to_mirek(20000) == 153   # clamp high-K
    assert kelvin_to_mirek(1000) == 500    # clamp low-K


def test_circadian_at_sunrise_is_warm_and_dim():
    st = circadian_state(at(11), SUNRISE, SUNSET)
    assert st["phase"] == "day" and st["day_fraction"] == 0.0
    assert st["kelvin"] == 2200
    assert st["payload"]["bri"] == 30
    assert st["payload"]["ct"] == kelvin_to_mirek(2200)


def test_circadian_at_solar_noon_is_cool_and_bright():
    noon = SUNRISE + (SUNSET - SUNRISE) / 2
    st = circadian_state(noon, SUNRISE, SUNSET)
    assert st["day_fraction"] == 0.5
    assert st["kelvin"] == 6500
    assert st["payload"]["bri"] == 254
    assert st["payload"]["ct"] == 154


def test_circadian_curve_is_symmetric():
    morning = circadian_state(SUNRISE + timedelta(hours=2), SUNRISE, SUNSET)
    evening = circadian_state(SUNSET - timedelta(hours=2), SUNRISE, SUNSET)
    assert morning["kelvin"] == evening["kelvin"]
    assert morning["payload"]["bri"] == evening["payload"]["bri"]


def test_circadian_night_is_dim_ember():
    st = circadian_state(at(4), SUNRISE, SUNSET)
    assert st["phase"] == "night" and st["day_fraction"] is None
    assert st["payload"]["bri"] == 15
    assert st["payload"]["on"] is True


def test_circadian_rejects_unusable_sun_times():
    assert circadian_state(at(12), None, SUNSET) is None
    assert circadian_state(at(12), SUNSET, SUNRISE) is None  # polar inversion


def test_circadian_from_space_payload():
    space = {"sun_times": {"sunrise_utc": SUNRISE.isoformat(),
                           "sunset_utc": SUNSET.isoformat()}}
    st = circadian_from_space(space, now=SUNRISE + (SUNSET - SUNRISE) / 2)
    assert st["kelvin"] == 6500
    assert circadian_from_space({"sun_times": {}}, now=at(12)) is None
    assert circadian_from_space({}, now=at(12)) is None


# -- briefing assembly ------------------------------------------------------
def _payloads():
    weather = {"ok": True, "unit_symbol": "°C",
               "location": {"city": "Phoenix"},
               "current": {"description": "Partly Cloudy", "temperature": 21.5,
                           "feels_like": 20.0, "weather_code": 2},
               "daily": [{"max": 26.0, "min": 14.0}]}
    solar = {"sunspot_number": 82.0, "solar_flux": 121.5,
             "geomagnetic": {"kp_index": 3, "label": "Quiet", "aurora_probability": 33}}
    news = {"articles": [{"source": "BBC", "display_title": "Seeded Headline One"}],
            "total_unread": 2}
    return weather, solar, news


def test_briefing_assembly():
    data = assemble_briefing(*_payloads(), now=datetime(2026, 10, 24, 9, 30))
    assert data["date"] == "Saturday, October 24, 2026"
    assert data["location"] == "Phoenix"
    assert "Partly Cloudy" in data["weather_summary"]
    assert "22°C" in data["weather_summary"]
    assert data["temp_range"] == "H 26° / L 14°"
    assert data["kp_index"] == 3 and data["kp_label"] == "Quiet"
    assert "Kp 3.0" in data["solar_summary"] and "sunspots 82" in data["solar_summary"]
    assert data["headline"] == "Seeded Headline One"
    assert data["headline_source"] == "BBC"
    assert data["version"] == "2.0.0"


def test_briefing_assembly_degrades_on_empty_panels():
    data = assemble_briefing({"ok": False}, {}, {"articles": []},
                             now=datetime(2026, 10, 24))
    assert data["weather_summary"] == "Weather unavailable"
    assert data["solar_summary"] == "Solar data unavailable"
    assert data["kp_index"] is None
    assert "No headlines" in data["headline"]


def test_briefing_png_render():
    pytest.importorskip("PIL")
    theme = themes.get_theme("cyberfire")
    png = render_briefing_png(assemble_briefing(*_payloads()), theme)
    assert png is not None and png[:8] == b"\x89PNG\r\n\x1a\n"
    assert len(png) > 5000


# -- Aurora Veil -------------------------------------------------------------
def test_aurora_veil_is_effect_101():
    veil = FX[-1]
    assert veil["id"] == "fx_101" and veil["name"] == "Aurora Veil"
    hues = [s["hue"] for s in veil["steps"]]
    assert min(hues) >= 25500 and max(hues) <= 53000      # green..violet band
    assert all(s["delay"] >= 2.0 for s in veil["steps"])  # slow drift
    assert hues[:6] == sorted(hues[:6])                   # rises green->violet
    assert hues[5:] == sorted(hues[5:], reverse=True)     # and drifts back


# -- endpoints ---------------------------------------------------------------
def test_briefing_endpoints(service):
    client = TestClient(create_app(service, service.cfg))
    r = client.get("/api/briefing")
    assert r.status_code == 200
    body = r.json()
    assert body["headline"].startswith("Seeded Headline")
    assert body["kp_index"] == 3
    r = client.get("/api/briefing.png")
    if r.status_code == 200:
        assert r.headers["content-type"] == "image/png"
        assert r.content[:8] == b"\x89PNG\r\n\x1a\n"
    else:  # Pillow absent: graceful 501 carrying the JSON briefing
        assert r.status_code == 501
        assert r.json()["briefing"]["headline"].startswith("Seeded Headline")


def test_circadian_endpoint_unconfigured_bridge(service):
    client = TestClient(create_app(service, service.cfg))
    r = client.post("/api/hue/circadian", json={})
    assert r.status_code == 200
    body = r.json()
    assert body["configured"] is False
    assert body["applied_to"] == 0
    assert body["phase"] in ("day", "night")
    assert 153 <= body["payload"]["ct"] <= 500
    assert 1 <= body["payload"]["bri"] <= 254


def test_hue_status_reports_sync_mode(service):
    client = TestClient(create_app(service, service.cfg))
    body = client.get("/api/hue/status").json()
    assert body["sync_mode"] == "conditions"
    r = client.post("/api/hue/sync", json={"mode": "circadian"})
    assert r.json()["sync_mode"] == "circadian"
