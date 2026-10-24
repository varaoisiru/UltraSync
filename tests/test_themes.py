from ultrasync import themes


def test_eight_canonical_themes():
    assert themes.theme_names() == [
        "cyberfire", "midnight", "phosphor", "solarflare",
        "aurora", "neonviolet", "deepocean", "toxicwaste",
    ]


def test_every_theme_complete():
    for name, t in themes.THEMES.items():
        for key in ("bg", "primary", "accent1", "accent2", "accent3", "dim"):
            assert t[key].startswith("#") and len(t[key]) == 7, (name, key)
        assert len(t["ramp"]) == 11, name
        for key in ("border", "header", "active", "sel_bg"):
            assert isinstance(t[key], int), (name, key)


def test_hex_conversions():
    assert themes.hex_to_ansi256("#00ff41").startswith("\033[38;5;")
    hue = themes.hex_to_hue("#ff0000")
    assert hue["hue"] == 0 and hue["sat"] == 254 and 1 <= hue["bri"] <= 254
    hue = themes.hex_to_hue("#0000ff")
    assert 43000 < hue["hue"] < 44000


def test_term_colors_all_themes():
    for name in themes.theme_names():
        c = themes.TermColors(name, force_256=True)
        assert c.border().startswith("\033[38;5;")
        assert c.ramp(0, 10).startswith("\033[")
        assert c.ramp(9, 10).startswith("\033[")
        assert c.sel_bg().startswith("\033[48;5;")


def test_next_theme_cycles():
    assert themes.next_theme("cyberfire") == "midnight"
    assert themes.next_theme("toxicwaste") == "cyberfire"
    assert themes.next_theme("bogus") == "midnight"  # falls back to first after index 0
