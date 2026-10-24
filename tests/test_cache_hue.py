import re
import time
from pathlib import Path

from ultrasync.cache import Cache
from ultrasync.hue import HueClient, condition_payload
from ultrasync.hue_fx import FX
from ultrasync import themes


def test_cache_round_trip(tmp_path):
    c = Cache(tmp_path / "c.db")
    assert c.get_fresh("missing") is None
    c.set("k", "v1")
    assert c.get_fresh("k") == "v1"
    data, fresh, age = c.get_with_age("k", max_age=900)
    assert data == "v1" and fresh and age < 5
    data, fresh, age = c.get_with_age("k", max_age=0)
    assert data == "v1" and not fresh  # stale data still readable


def test_fx_table_complete():
    assert len(FX) == 100
    for fx in FX:
        assert fx["name"] and fx["description"]
        assert len(fx["steps"]) >= 1, fx["id"]
        for step in fx["steps"]:
            assert 0 <= step["hue"] <= 65535
            assert 0 <= step["sat"] <= 254
            assert 0 <= step["bri"] <= 254  # 0 appears in the original strobe/off steps
            assert step["delay"] >= 0


def test_no_secrets_in_fx_source():
    src = Path(__file__).resolve().parents[1] / "ultrasync" / "hue_fx.py"
    text = src.read_text()
    assert not re.search(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", text)  # no IPs
    assert not re.search(r"[A-Za-z0-9]{30,}", text)             # no long tokens


def test_hue_client_unconfigured():
    client = HueClient(None, None)
    assert client.configured is False
    assert client.get_lights() == {}
    assert client.set_state(1, {"on": True}) is False


def test_condition_payload_mapping():
    theme = themes.get_theme("cyberfire")
    assert condition_payload(0, 8.0, theme)["hue"] == 0        # Kp 8 -> red alert
    assert condition_payload(0, 5.5, theme)["hue"] == 8000      # Kp 5.5 -> orange
    assert condition_payload(63, 1.0, theme)["hue"] == 42000    # rain -> blue
    assert condition_payload(0, 1.0, theme)["hue"] == themes.hex_to_hue("#00ff41", bri=190)["hue"]
