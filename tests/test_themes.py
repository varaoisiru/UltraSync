from ultrasync import themes


CANONICAL = [
    "cyberfire", "midnight", "phosphor", "solarflare",
    "aurora", "neonviolet", "deepocean", "toxicwaste",
]


def test_eight_canonical_themes():
    # The canonical eight are unchanged and still come first; the 500
    # mesh-generated variations (themes_extra.json) follow them.
    names = themes.theme_names()
    assert names[:8] == CANONICAL
    assert len(names) == 508


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
    names = themes.theme_names()
    assert themes.next_theme("toxicwaste") == names[8]  # into the variations
    assert themes.next_theme(names[-1]) == "cyberfire"  # wraps the full set
    assert themes.next_theme("bogus") == "midnight"  # falls back to first after index 0
