# UltraSync 2.3.0

**One dashboard for news, weather, solar activity, and space — in a retro
phosphor skin, on the web and in your terminal.**

UltraSync is the unified successor to two projects that grew from the same
root: **Ultrareader**, a vintage terminal RSS news reader, and **SolarSync**,
its weather/solar/space evolution ("an evolution of Ultrareader"). Instead of
two apps with two configs, two caches, two theme engines and two copies of
the same Hue script, UltraSync merges them into a single application:

- one **web GUI** (flagship) and one **terminal UI**, sharing one data layer
- one theme engine — the 8 retro themes skin *every* panel, GUI and TUI alike
- one SQLite store for API cache + news articles
- one Philips Hue integration, ported from bash to Python, credentials from
  config/env only
- one config file, with automatic migration from both parents' configs

The GUI is a single-page app: NEWS feed with source filters,
search and an in-app article reader; WEATHER with current conditions, a canvas
24-hour temperature curve and a 7-day outlook; SOLAR with sunspot/flux/Kp
gauges and a Kp forecast chart; SPACE with sun & moon times, a rendered moon
phase disc, real computed planet positions, and the live ISS position; and a
HUE panel with per-light control, the 101-effect FX library, and
sync-to-conditions lighting.

## What's new in 2.0

- **Command palette** — Ctrl/Cmd+K opens a fuzzy-search overlay that jumps
  to panels, switches themes, plays Hue effects, and runs actions
  (refresh, units, ambient mode, briefing card) without touching the mouse.
- **Ambient mode** — a full-screen kiosk view cycling the top headline,
  weather, Kp state, and moon in oversized type with slow crossfades.
  The iOS app gains a matching Ambient tab.
- **Kp-reactive UI** — an animated aurora-ribbon background whose speed,
  thickness, and color track the live Kp index, plus a pulsing storm
  banner whenever Kp reaches 5. iOS answers with an animated Kp gauge
  (spring sweep + needle + storm halo).
- **Daily briefing card** — `GET /api/briefing` assembles the day's
  weather, solar summary, and top headline; `GET /api/briefing.png`
  renders it as a shareable 1200×630 PNG in the active theme (Pillow;
  degrades to the JSON form when Pillow is absent).
- **Circadian solar sync** — a second Hue sync engine: color temperature
  and brightness follow the sun (2200K at the horizons, 6500K at solar
  noon, dim ember overnight), computed from the space module's NOAA
  sunrise/sunset. Choose it next to the Sync toggle or fire it once
  from the Hue panel / palette.
- **Aurora Veil** — effect #101 in the FX library: a slow green →
  teal → violet drift, hand-authored alongside the ported 100.

## Quick start

```bash
./run.sh                 # bootstraps a venv on first run, serves the GUI
# → http://127.0.0.1:8077
```

Or install system-wide (launcher in `~/.local/bin`):

```bash
./install.sh
ultrasync                # GUI
ultrasync --tui          # terminal UI
ultrasync --once         # render one full frame to stdout (headless check)
ultrasync --export-html snapshot.html
```

Platform packaging: **Windows** — `windows/install.bat`, `windows/run.bat`,
and a PyInstaller spec (`windows/ultrasync.spec`, see
`windows/README-WINDOWS.md`). **Arch Linux** — `arch/PKGBUILD`,
`arch/install.sh`, and a systemd `--user` unit (see `arch/README-ARCH.md`).

## Using the GUI

Open http://127.0.0.1:8077. Everything on the page is live:

- **Theme swatches** (top right) re-skin the whole app instantly and persist.
  The °C/°F chip toggles units.
- **⌘K / Ctrl+K** opens the command palette; **Ambient** starts the
  full-screen cycling highlight view (click or Esc exits). The background
  ribbons react to the live Kp index, and a storm banner appears at Kp ≥ 5.
- **NEWS** — click a headline to read it in the built-in reader (article text
  is fetched and cleaned server-side); source chips filter, the search box
  searches titles and summaries, ● marks unread. ↻ Refresh re-fetches feeds.
- **WEATHER / SOLAR / SPACE** — refresh themselves every minute (ISS every
  30 s). Panel badges read LIVE or CACHED; if the network drops, the last
  data stays on screen with a CACHED badge instead of an error page.
- **HUE** — with a bridge configured you get real light toggles and
  brightness sliders, the 101-effect library (▶ Play FX), and two sync
  engines: *Sync to conditions*, which pushes lighting derived from the
  live weather/Kp/theme, and *circadian* sync, which tracks the sun's
  position through the day. Without a bridge the panel shows a clean
  unconfigured state with setup instructions.

## Terminal UI

SolarSync's keyboard model, extended to four panels:

| Key | Action | Key | Action |
|---|---|---|---|
| A / D | Previous / next panel | C | Cycle theme |
| W / S | Navigate | F | Toggle °C/°F |
| Enter | Read article (News) | T | Toggle 12h/24h |
| O | Open in browser (News) | X | Hue on/off |
| M | Mark all read (News) | R | Refresh |
| Q | Quit (back, in reader) | | |

## What each parent contributed

| From Ultrareader | From SolarSync |
|---|---|
| RSS/Atom feed engine (news/tech/science categories) | Open-Meteo weather (current/hourly/7-day) |
| Article store with read/unread, search, source filter | NOAA SWPC solar indices, solar wind, Kp |
| Article reader with text cleaner (Jina → lynx fallback) | Sun/moon, planets, ISS modules |
| 256-color theme ramps, terminal input/mouse handling | 8 hex theme palettes, box-drawing dashboard |
| Pi CPU temperature, MST clock, status bar | IP geolocation, config/cache layout |
| hue_pro.sh — 100-effect bash Hue engine | hue_sync.sh — the same engine, byte-identical |

Verified during the merge: `hue_pro.sh` and `hue_sync.sh` were byte-identical
(635 lines each), and `ultra.py` was a strict subset of `ultratwo.py` (same
functions and theme table; ultratwo generalizes the feed categories), so the
news panel is built on `ultratwo.py` and nothing from `ultra.py` was lost.

## Architecture

```
                        ┌─────────────────────────────┐
   Browser (SPA) ──────▶│  FastAPI JSON API (api.py)  │
   vanilla JS + canvas  └──────────────┬──────────────┘
                                       │ shared
   Terminal UI (tui.py) ───────▶ DataService (service.py)
                                       │
        ┌──────────────┬───────────────┼───────────────┬──────────────┐
        ▼              ▼               ▼               ▼              ▼
   news.py       weather.py       solar.py        space.py        hue.py
   RSS/Atom      Open-Meteo       NOAA SWPC       sun/moon calc   Hue REST
   + articles    + WMO codes      indices/wind/Kp planets (JPL)   + 101 FX
        └──────────────┴───────────────┴───────────────┘
                        │               │
                   cache.py        config.py + themes.py
                 SQLite (cache +    ~/.config/ultrasync/
                  articles)         config.json · 8 themes
```

Data modules are stdlib-only; FastAPI/uvicorn are the only hard runtime
dependencies (Pillow renders the briefing-card PNG and is optional —
without it the card endpoint degrades to JSON). Space data is computed locally (NOAA sunrise/sunset algorithm,
synodic moon phase with true illumination, JPL approximate planet elements
converted to topocentric alt/az) with Open-Meteo and wheretheiss.at as live
enhancements — so the app works offline from cache and computation, and the
parents' placeholder planet table is gone.

## Configuration

`~/.config/ultrasync/config.json` (created on first run; legacy
`~/.config/ultra/` and `~/.config/solarsync/` configs are migrated
automatically). Sections: `location` (auto-IP or manual lat/lon),
`preferences` (units, time format, refresh, theme, mouse, Pi temp), `hue`
(`bridge_ip`, `api_key`, `lights`, `sync_conditions`, `sync_mode` —
`conditions` or `circadian`), `display`, `feeds`
(category → [name, url] pairs), `server` (host/port).

Hue credentials can also come from the environment: `HUE_BRIDGE_IP`,
`HUE_API_KEY`. **No credentials exist anywhere in this repository** — the
parent repos' bash script contained a hardcoded bridge key; it was excluded
from the port and must be rotated if it was ever shared (it also remains in
the parent repos' git history — treat it as compromised).

## Data sources (all free, no keys)

Open-Meteo (weather, sun/moon times) · NOAA SWPC (solar indices, RTSW solar
wind, planetary K index, region summary, K forecast) · ip-api (geolocation) ·
wheretheiss.at (ISS position) · your RSS/Atom feeds · NASA DEMO_KEY endpoints
are not required by any module.

## Tests

```bash
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest tests/ -q
```

53 tests: config load/merge/legacy migration, theme engine (all 8 themes),
RSS + Atom parsing on fixtures, the FOX undated-entry rule, the article
cleaner, sun/moon math against known values, cache freshness round-trips,
the FX table (101 effects, range-checked, secret-scanned), every API
endpoint including the SPA, the `--once` / `--export-html` headless runs,
plus the 2.0 additions: the circadian curve (sunrise/noon/night, mirek
clamps, symmetry), briefing-card assembly and PNG rendering, and the
circadian / sync-mode endpoints.

## Benchmarks & influences

UltraSync is a hand-rolled ANSI/stdlib codebase, but it is measured against
the modern TUI standards: **Textual** (>28k GitHub stars) for what a polished
terminal interface should feel like, and **Rich** (>50k stars) for rendering
discipline (measurement, wrapping, markup safety). The web GUI deliberately
stays dependency-free vanilla JS + canvas in the same spirit as the parents:
no build step, nothing between the code and the metal.

## Version

2.3.0 — the theme picker is organized: a dropdown panel groups the
508 themes by family (Canonical, Deep Sea, Jewel Tones, Desert &
Canyon, Storm & Slate, Forest & Moss, …) with a live search, instead
of one endless strip of swatches.
2.2.0 — 500 mesh-generated theme variations (themes_extra.json) join
the canonical eight: 508 themes drive the web GUI, TUI, export, and
Hue sync. The extra set loads failure-safe — a missing or corrupt
file leaves the canonical eight untouched.
2.1.1 — bug fix: the weather and Kp charts grew taller on every
redraw (fitCanvas read back its own DPR-scaled height attribute and
multiplied again), eventually filling the whole screen. Chart
heights are now pinned to their declared CSS size.
2.1.0 — imperial units by default (wind in mph, precipitation in
inches), and the Kp aurora background is compact: the ribbons hug a
shallow band at the top of the screen instead of sweeping full height.
2.0.0 — command palette, ambient mode (web + iOS), Kp-reactive UI and
storm banner, daily briefing card, circadian solar sync, Aurora Veil.
1.0.0 — first unified release.
