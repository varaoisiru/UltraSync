"""Unified SQLite storage.

One database (~/.cache/ultrasync/ultrasync.db) holds both parents'
tables:
- `cache`    — SolarSync's key/value API response cache with timestamps
- `articles` — Ultrareader's news article store with read/unread tracking

Freshness is explicit: get_entry() returns data + age so callers can
serve stale data with a visible "cached" status instead of failing.
"""
import sqlite3
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from . import config as cfgmod


class Cache:
    def __init__(self, db_path: Path = None):
        self.db_path = Path(db_path) if db_path else cfgmod.cache_db()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._init_tables()

    def _connect(self):
        return sqlite3.connect(str(self.db_path), check_same_thread=False)

    def _init_tables(self):
        with self._lock, self._connect() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS cache (
                    key TEXT PRIMARY KEY,
                    data TEXT,
                    timestamp INTEGER
                );
                CREATE TABLE IF NOT EXISTS articles (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source TEXT,
                    title TEXT,
                    link TEXT UNIQUE,
                    summary TEXT,
                    fetched_at INTEGER,
                    viewed INTEGER DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_time ON articles(fetched_at);
            """)

    # -- key/value API cache (SolarSync) --------------------------------
    def get_entry(self, key: str) -> Optional[Tuple[str, int]]:
        """Return (data, timestamp) regardless of age, or None."""
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT data, timestamp FROM cache WHERE key = ?", (key,)
            ).fetchone()
        if row:
            return row[0], row[1]
        return None

    def get_fresh(self, key: str, max_age: int = 900) -> Optional[str]:
        entry = self.get_entry(key)
        if entry and (time.time() - entry[1]) < max_age:
            return entry[0]
        return None

    def get_with_age(self, key: str, max_age: int = 900):
        """Return (data_or_None, is_fresh, age_seconds)."""
        entry = self.get_entry(key)
        if not entry:
            return None, False, None
        age = time.time() - entry[1]
        return entry[0], age < max_age, age

    def set(self, key: str, data: str):
        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO cache (key, data, timestamp) VALUES (?, ?, ?)",
                (key, data, int(time.time())),
            )

    # -- article store (Ultrareader) -------------------------------------
    def save_articles(self, articles: List[Dict]):
        now = int(time.time())
        with self._lock, self._connect() as conn:
            for a in articles:
                try:
                    conn.execute(
                        """INSERT OR IGNORE INTO articles
                           (source, title, link, summary, fetched_at)
                           VALUES (?, ?, ?, ?, ?)""",
                        (a.get("source", ""), a["title"], a["link"],
                         (a.get("summary") or "")[:500], now),
                    )
                except Exception:
                    continue

    def load_articles(self, search: str = "", source: Optional[str] = None,
                      limit: int = 200) -> List[Dict]:
        clauses, params = [], []
        if search:
            clauses.append("(title LIKE ? OR summary LIKE ?)")
            like = f"%{search}%"
            params += [like, like]
        if source:
            clauses.append("source = ?")
            params.append(source)
        where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                f"""SELECT source, title, link, summary, fetched_at, viewed
                    FROM articles {where}
                    ORDER BY fetched_at DESC LIMIT ?""",
                params + [limit],
            ).fetchall()
        return [
            {"source": r[0], "title": r[1], "link": r[2], "summary": r[3],
             "fetched_at": r[4], "viewed": r[5]}
            for r in rows
        ]

    def mark_viewed(self, link: str):
        with self._lock, self._connect() as conn:
            conn.execute("UPDATE articles SET viewed = 1 WHERE link = ?", (link,))

    def mark_all_viewed(self, source: Optional[str] = None):
        with self._lock, self._connect() as conn:
            if source:
                conn.execute("UPDATE articles SET viewed = 1 WHERE source = ?", (source,))
            else:
                conn.execute("UPDATE articles SET viewed = 1")

    def count_unread(self, source: Optional[str] = None) -> int:
        with self._lock, self._connect() as conn:
            if source:
                row = conn.execute(
                    "SELECT COUNT(*) FROM articles WHERE viewed = 0 AND source = ?",
                    (source,)).fetchone()
            else:
                row = conn.execute(
                    "SELECT COUNT(*) FROM articles WHERE viewed = 0").fetchone()
        return row[0] if row else 0

    def purge_old(self, days: int = 7):
        cutoff = int(time.time()) - (days * 86400)
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM articles WHERE fetched_at < ?", (cutoff,))
