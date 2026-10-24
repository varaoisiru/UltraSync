from pathlib import Path

from ultrasync import news

FIXTURE = Path(__file__).parent / "fixtures" / "sample_feed.xml"


def test_parse_rss_fixture():
    entries = news.parse_feed(FIXTURE.read_bytes())
    assert len(entries) == 3
    first = entries[0]
    assert first["title"] == "Solar Storm Approaches Earth"
    assert first["link"] == "https://example.com/articles/solar-storm"
    assert "geomagnetic storm" in first["summary"]
    assert "<p>" not in first["summary"]  # HTML stripped
    assert first["published"] is not None
    assert entries[2]["published"] is None  # undated brief


def test_parse_atom():
    atom = b"""<?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Fixture</title>
      <entry><title>Atom Story</title>
        <link href="https://example.com/atom"/>
        <summary>Atom summary text</summary>
        <published>2026-10-24T08:00:00Z</published></entry>
    </feed>"""
    entries = news.parse_feed(atom)
    assert len(entries) == 1
    assert entries[0]["title"] == "Atom Story"
    assert entries[0]["link"] == "https://example.com/atom"
    assert entries[0]["published"] is not None


def test_parse_garbage_returns_empty():
    assert news.parse_feed(b"not xml at all") == []
    assert news.parse_feed(b"") == []


def test_store_round_trip(cache):
    from ultrasync.news import fetch_all_feeds
    from ultrasync.config import Config
    import ultrasync.net as net

    original = net.fetch_bytes
    net.fetch_bytes = lambda url, timeout=8, headers=None: FIXTURE.read_bytes()
    try:
        cfg = Config()
        cfg.data["feeds"] = {"news": [["BBC", "https://example.com/feed"]]}
        count = fetch_all_feeds(cfg, cache)
    finally:
        net.fetch_bytes = original
    assert count == 3
    arts = cache.load_articles()
    assert len(arts) == 3
    assert arts[0]["title"].startswith("[BBC] ")
    assert cache.count_unread() == 3
    cache.mark_viewed(arts[0]["link"])
    assert cache.count_unread() == 2
    found = cache.load_articles(search="Night Sky")
    assert len(found) == 1 and "Night Sky" in found[0]["title"]


def test_fox_undated_entries_skipped(cache):
    from ultrasync.news import fetch_all_feeds
    from ultrasync.config import Config
    import ultrasync.net as net

    original = net.fetch_bytes
    net.fetch_bytes = lambda url, timeout=8, headers=None: FIXTURE.read_bytes()
    try:
        cfg = Config()
        cfg.data["feeds"] = {"news": [["FOX", "https://example.com/fox"]]}
        count = fetch_all_feeds(cfg, cache)
    finally:
        net.fetch_bytes = original
    assert count == 2  # the undated brief is skipped for FOX


def test_clean_article_text():
    raw = ("By Some Reporter\n\n"
           "This is a genuine paragraph of article body text that is long "
           "enough to survive the cleaner and should be kept in the output.\n\n"
           "Advertisement\n\n"
           "Another real paragraph follows here with substantive content "
           "for the reader to actually read in the terminal interface.")
    paras = news.clean_article_text(raw)
    assert len(paras) == 2
    assert all("Advertisement" not in p for p in paras)
