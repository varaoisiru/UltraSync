from fastapi.testclient import TestClient

from ultrasync.api import create_app


def make_client(service):
    return TestClient(create_app(service, service.cfg))


def test_spa_served(service):
    r = make_client(service).get("/")
    assert r.status_code == 200
    assert "ULTRASYNC" in r.text
    assert "/static/app.js" in r.text


def test_status(service):
    r = make_client(service).get("/api/status")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True and body["version"] == "2.0.0"
    assert body["unread"] == 2


def test_news_endpoint(service):
    r = make_client(service).get("/api/news")
    assert r.status_code == 200
    body = r.json()
    assert body["count"] == 2
    assert body["articles"][0]["display_title"].startswith("Seeded")
    assert "BBC" in body["sources"]


def test_weather_endpoint(service):
    r = make_client(service).get("/api/weather")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    # default units are imperial: 21.5 C -> 70.7 F, 12 km/h -> 7.5 mph
    assert body["current"]["temperature"] == 70.7
    assert body["unit_symbol"] == "°F"
    assert body["wind_unit"] == "mph"
    assert body["precip_unit"] == "in"
    assert body["current"]["wind_speed"] == 7.5
    assert body["current"]["description"] == "Partly Cloudy"
    assert len(body["daily"]) == 7
    assert len(body["hourly"]) > 0


def test_solar_endpoint(service):
    r = make_client(service).get("/api/solar")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["sunspot_number"] == 82.0
    assert body["geomagnetic"]["kp_index"] == 3


def test_space_endpoint(service):
    r = make_client(service).get("/api/space")
    assert r.status_code == 200
    body = r.json()
    assert len(body["planets"]) == 5
    assert 0 <= body["moon_data"]["phase"] <= 1
    assert body["sun_times"].get("sunrise_utc")


def test_themes_endpoint_and_switch(service):
    client = make_client(service)
    r = client.get("/api/themes")
    assert r.status_code == 200
    assert len(r.json()["themes"]) == 8
    r = client.post("/api/theme", json={"name": "aurora"})
    assert r.json()["active"] == "aurora"
    r = client.post("/api/theme", json={"name": "nope"})
    assert r.status_code == 400


def test_config_endpoint_redacts(service):
    r = make_client(service).get("/api/config")
    assert r.status_code == 200
    assert r.json()["hue"]["api_key"] is None


def test_hue_status_unconfigured(service):
    r = make_client(service).get("/api/hue/status")
    assert r.status_code == 200
    body = r.json()
    assert body["configured"] is False
    assert body["api_key_set"] is False
    assert body["lights"] == []


def test_hue_fx_list(service):
    r = make_client(service).get("/api/hue/fx")
    assert r.status_code == 200
    effects = r.json()["effects"]
    assert len(effects) == 101
    assert effects[0]["name"] == "Aurora Sweep"
    assert effects[-1]["name"] == "Aurora Veil"
