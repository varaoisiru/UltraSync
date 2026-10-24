from datetime import datetime, timezone

from ultrasync import space


def test_moon_phase_known_new_moon():
    phase = space.moon_phase(datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc))
    assert phase < 0.01 or phase > 0.99
    assert space.moon_illumination(phase) < 0.01


def test_moon_phase_known_full_moon():
    # Full moon: 2000-01-21 04:40 UTC (also a lunar eclipse).
    phase = space.moon_phase(datetime(2000, 1, 21, 4, 40, tzinfo=timezone.utc))
    assert 0.47 < phase < 0.53
    assert space.moon_illumination(phase) > 0.97
    assert space.moon_phase_name(phase) == "Full Moon"
    assert space.moon_phase_icon(phase) == "🌕"


def test_moon_phase_names_cover_cycle():
    names = {space.moon_phase_name(p / 8 + 0.01) for p in range(8)}
    assert len(names) == 8


def test_sun_times_phoenix_october():
    # Phoenix, Sat 2026-10-24: sunrise ≈ 06:34 MST (13:34 UTC),
    # sunset ≈ 17:37 MST (00:37 UTC next day). Tolerance 15 minutes.
    rise, set_ = space.sun_times(datetime(2026, 10, 24, tzinfo=timezone.utc),
                                 33.4484, -112.0740)
    assert rise is not None and set_ is not None
    assert abs((rise.hour * 60 + rise.minute) - (13 * 60 + 34)) <= 15
    sunset_minutes = set_.hour * 60 + set_.minute + (1440 if set_.day != rise.day else 0)
    assert abs(sunset_minutes - (24 * 60 + 37)) <= 15


def test_planet_positions_structure():
    planets = space.planet_positions(
        datetime(2026, 10, 24, 12, 0, tzinfo=timezone.utc), 33.4484, -112.0740)
    assert [p["name"] for p in planets] == ["Mercury", "Venus", "Mars", "Jupiter", "Saturn"]
    for p in planets:
        assert -90 <= p["altitude"] <= 90
        assert 0 <= p["azimuth"] < 360
        assert p["visible"] == (p["altitude"] > 0)


def test_planets_move_over_time():
    a = space.planet_positions(datetime(2026, 1, 1, tzinfo=timezone.utc), 40.0, -74.0)
    b = space.planet_positions(datetime(2026, 7, 1, tzinfo=timezone.utc), 40.0, -74.0)
    assert any(abs(x["altitude"] - y["altitude"]) > 1 for x, y in zip(a, b))
