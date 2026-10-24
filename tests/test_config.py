import json

from ultrasync.config import Config, deep_merge


def test_defaults_present(cfg):
    assert cfg.get("preferences", "theme") == "cyberfire"
    assert cfg.get("preferences", "units") == "metric"
    assert cfg.get("hue", "lights") == [1, 6]
    assert "news" in cfg.get("feeds")
    assert cfg.get("server", "port") == 8077


def test_deep_merge_keeps_nested_defaults():
    merged = deep_merge({"a": {"x": 1, "y": 2}}, {"a": {"y": 3}})
    assert merged == {"a": {"x": 1, "y": 3}}


def test_save_load_round_trip(tmp_path):
    path = tmp_path / "c.json"
    c1 = Config(path)
    c1.set("preferences", "theme", value="aurora")
    c1.set("hue", "bridge_ip", value="192.0.2.10")
    c2 = Config(path)
    assert c2.get("preferences", "theme") == "aurora"
    assert c2.get("hue", "bridge_ip") == "192.0.2.10"
    # untouched defaults survive the round trip
    assert c2.get("preferences", "units") == "metric"


def test_public_dict_redacts_key(tmp_path, monkeypatch):
    monkeypatch.setenv("HUE_API_KEY", "test-key-value")
    c = Config(tmp_path / "c.json")
    pub = c.public_dict()
    assert pub["hue"]["api_key"] is None
    assert pub["hue"]["api_key_set"] is True
    assert pub["hue"]["configured"] is False  # no bridge ip yet
    assert "test-key-value" not in json.dumps(pub)


def test_legacy_migration(tmp_path, monkeypatch):
    home = tmp_path / "home"
    (home / ".config" / "ultra").mkdir(parents=True)
    (home / ".config" / "solarsync").mkdir(parents=True)
    (home / ".config" / "ultra" / "config.json").write_text(json.dumps({
        "theme": "phosphor", "refresh_minutes": 30, "enable_pi_temp": False,
        "mouse_enabled": False,
        "feeds": {"news": [["BBC", "http://feeds.bbci.co.uk/news/rss.xml"]]},
    }))
    (home / ".config" / "solarsync" / "config.json").write_text(json.dumps({
        "location": {"city": "Flagstaff", "auto_ip": False},
        "hue": {"lights": [2, 3]},
    }))
    monkeypatch.setenv("HOME", str(home))
    c = Config(tmp_path / "fresh.json")
    assert c.get("preferences", "theme") == "phosphor"
    assert c.get("preferences", "refresh_minutes") == 30
    assert c.get("preferences", "enable_mouse") is False
    assert c.get("location", "city") == "Flagstaff"
    assert c.get("hue", "lights") == [2, 3]
    # legacy feeds carry over; categories the legacy config lacked are
    # filled from UltraSync defaults rather than dropped
    assert c.get("feeds")["news"] == [["BBC", "http://feeds.bbci.co.uk/news/rss.xml"]]
    assert "tech" in c.get("feeds") and "science" in c.get("feeds")
