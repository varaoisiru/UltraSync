"""News module — Ultrareader's feed engine, ported and unified.

Feeds come from the unified config (Ultrareader's news/tech/science
categories). Parsing uses the standard library (RSS 2.0 + Atom) so the
app has zero runtime dependencies; article storage, read/unread
tracking, search, and the article-text cleaner are Ultrareader's.
"""
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from typing import Dict, List, Optional

from . import net

ATOM = "{http://www.w3.org/2005/Atom}"


def _parse_date(text: Optional[str]) -> Optional[int]:
    if not text:
        return None
    text = text.strip()
    try:
        dt = parsedate_to_datetime(text)
        if dt is not None:
            return int(dt.timestamp())
    except Exception:
        pass
    try:
        from datetime import datetime
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return int(dt.timestamp())
    except Exception:
        return None


def _strip_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text or "")
    return " ".join(text.split())


def parse_feed(content: bytes) -> List[Dict]:
    """Parse RSS 2.0 or Atom bytes into entry dicts.

    Each entry: {title, link, summary, published (epoch|None)}.
    Raises nothing — unparseable input returns [].
    """
    entries: List[Dict] = []
    if not content:
        return entries
    try:
        root = ET.fromstring(content)
    except Exception:
        return entries

    if root.tag.endswith("feed"):  # Atom
        for e in root.iter(f"{ATOM}entry"):
            title = e.findtext(f"{ATOM}title", "") or ""
            link = ""
            for lnk in e.findall(f"{ATOM}link"):
                if lnk.get("rel") in (None, "alternate"):
                    link = lnk.get("href", "")
                    break
            summary = e.findtext(f"{ATOM}summary", "") or e.findtext(f"{ATOM}content", "") or ""
            published = _parse_date(e.findtext(f"{ATOM}published") or e.findtext(f"{ATOM}updated"))
            entries.append({"title": title.strip(), "link": link.strip(),
                            "summary": _strip_html(summary), "published": published})
        return entries

    # RSS 2.0 / RDF
    for item in root.iter("item"):
        title = item.findtext("title", "") or ""
        link = item.findtext("link", "") or ""
        summary = item.findtext("description", "") or ""
        published = _parse_date(item.findtext("pubDate") or item.findtext("{http://purl.org/dc/elements/1.1/}date"))
        entries.append({"title": title.strip(), "link": link.strip(),
                        "summary": _strip_html(summary), "published": published})
    return entries


def fetch_all_feeds(cfg, store) -> int:
    """Fetch every configured feed into the article store.

    Preserves Ultrareader's behavior: top 10 entries per feed, titles
    stored with a [SOURCE] prefix, FOX entries without a publication
    date are skipped, articles older than 7 days are purged.
    """
    count = 0
    feeds = cfg.get("feeds", default={}) or {}
    for _category, feed_list in feeds.items():
        for name, url in feed_list:
            raw = net.fetch_bytes(url, timeout=8)
            if not raw:
                continue
            for e in parse_feed(raw)[:10]:
                if name == "FOX" and not e.get("published"):
                    continue
                if not e.get("title") or not e.get("link"):
                    continue
                store.save_articles([{
                    "source": name,
                    "title": f"[{name}] {e['title']}",
                    "link": e["link"],
                    "summary": e.get("summary", ""),
                }])
                count += 1
    store.purge_old(days=7)
    return count


# -- article body extraction (Ultrareader) ------------------------------
_JUNK_PATTERNS = [
    r'^\s*[\+\*]\s', r'Expand/Collapse', r'\(BUTTON\)', r'Menu\s+\+',
    r'Trending\s+Deals', r'Gift\s+Guides', r'Home\s+Deals', r'Kitchen\s+Deals',
    r'Tech\s+and\s+Electronic', r'Health\s+and\s+Fitness', r'Beauty\s+and\s+Fashion',
    r'FOX\s+Business', r'FOX\s+News\s+Shows', r'Watch\s+Live', r'Apps\s+&\s+Products',
    r'Newsletters', r'Podcasts', r'FOX\s+Nation', r'FOX\s+Weather', r'FOX\s+News\s+Go',
    r'Sudoku', r'Crossword', r'Word\s+Search', r'5\s+Across', r'DownWords',
    r'Swap\s+Words', r'Icon\s+Match', r'Scattergories',
    r'More\s+from', r'Related\s+Articles', r'Also\s+on', r'Continue\s+Reading',
    r'Advertisement', r'Sponsored', r'Follow\s+Us', r'Share\s+this',
    r'Facebook', r'Twitter', r'Instagram', r'YouTube', r'LinkedIn', r'Reddit',
    r'Flipboard', r'Print', r'Email', r'Copy\s+Link',
    r'^\s*\d+\.\s+', r'^\s*Read\s+More', r'^\s*Click\s+here',
    r'^\s*Sign\s+up', r'^\s*Subscribe',
]
_JUNK_RE = re.compile("|".join(f"({p})" for p in _JUNK_PATTERNS), re.IGNORECASE)


def clean_article_text(raw: str) -> List[str]:
    """Ultrareader's paragraph cleaner, unchanged in behavior."""
    paragraphs = []
    for chunk in raw.split("\n\n"):
        clean = " ".join(chunk.split())
        if len(clean) < 60:
            continue
        if _JUNK_RE.search(clean):
            continue
        if len(clean) < 100 and clean.upper() == clean:
            continue
        if re.match(r"^\s*(By|Published|Updated|Posted)\s", clean, re.I):
            continue
        paragraphs.append(clean)
    if not paragraphs:
        paragraphs = ["[Article text could not be extracted cleanly]"]
    return paragraphs


def fetch_article_paragraphs(url: str) -> List[str]:
    """Fetch + clean an article body: Jina reader first, lynx fallback."""
    content = ""
    clean_url = url.split("://", 1)[-1]
    text = net.fetch_text(f"https://r.jina.ai/http://{clean_url}", timeout=8,
                          headers={"User-Agent": "Mozilla/5.0"})
    if text and len(text) > 100:
        content = text
    if not content:
        try:
            curl = subprocess.Popen(["curl", "-s", "-L", "-A", "Mozilla/5.0", url],
                                    stdout=subprocess.PIPE)
            lynx = subprocess.Popen(
                ["lynx", "-stdin", "-dump", "-nolist",
                 "-display_charset=utf-8", "-width=2000"],
                stdin=curl.stdout, stdout=subprocess.PIPE)
            curl.stdout.close()
            content = lynx.communicate()[0].decode("utf-8", errors="ignore")
        except Exception:
            content = ""
    if not content:
        return ["Failed to pull article content dynamically."]
    return clean_article_text(content)
