"""Terminal UI — UltraSync's secondary interface.

SolarSync's keyboard model and dashboard layout, extended with
Ultrareader's news panel and article reader. All four panels render
from the same DataService the web GUI uses.

Keys: A/D switch panel · W/S navigate · Enter read article (News) ·
R refresh · C theme · F units · T time format · X Hue on/off · Q quit
"""
import sys
import textwrap
from datetime import datetime

from . import themes
from .config import Config
from .hue import HueClient, condition_payload
from .service import DataService
from .term import InputHandler, get_pi_temp, open_in_browser, rel_age, vpad

PANELS = ["NEWS", "WEATHER", "SOLAR", "SPACE"]
W = 100


def _bar(value, width=15, min_val=0, max_val=100):
    try:
        value = float(value)
    except (TypeError, ValueError):
        value = 0
    norm = (value - min_val) / (max_val - min_val) if max_val > min_val else 0
    norm = max(0.0, min(1.0, norm))
    filled = int(norm * width)
    return "[" + "█" * filled + "░" * (width - filled) + "]"


class Tui:
    def __init__(self, cfg: Config = None, service: DataService = None):
        self.cfg = cfg or Config()
        self.service = service or DataService(self.cfg)
        self.panel = 0
        self.sel = 0
        self.scroll = 0
        self.hue_enabled = bool(self.cfg.get("preferences", "enable_hue", default=False))
        self._news = {"articles": []}
        self._weather = {}
        self._solar = {}
        self._space = {}
        self.refresh()

    # -- data -------------------------------------------------------------
    def refresh(self):
        self._weather = self.service.get_weather()
        self._solar = self.service.get_solar()
        self._space = self.service.get_space()
        self._news = self.service.get_news(limit=200)

    def colors(self):
        return themes.TermColors(self.cfg.get("preferences", "theme", default="cyberfire"))

    # -- frame pieces -------------------------------------------------------
    def header(self, c) -> str:
        loc = self.service.location()
        city = loc.get("city") or "Unknown"
        wx = self._weather.get("current", {}) if self._weather.get("ok") else {}
        temp = wx.get("temperature")
        unit = self._weather.get("unit_symbol", "")
        temp_s = f"{temp:.0f}{unit}" if isinstance(temp, (int, float)) else "--"
        now = datetime.now().strftime("%H:%M:%S")
        tabs = "  ".join(
            f"{c.active()}▶{c.CR} {name}" if i == self.panel else f"  {name}"
            for i, name in enumerate(PANELS))
        lines = [
            f"{c.border()}╭{'─' * (W - 2)}╮{c.CR}",
            f"{c.border()}│{c.CR} {c.header()}ULTRASYNC{c.CR} {tabs}"
            + " " * max(0, W - 4 - 9 - len("  ".join(PANELS)) * 2 - len(city) - len(now) - len(temp_s))
            + f"{c.hex('accent2')}{city} {temp_s} {now}{c.CR} {c.border()}│{c.CR}",
            f"{c.border()}├{'─' * (W - 2)}┤{c.CR}",
        ]
        return "\n".join(lines)

    def footer(self, c) -> str:
        theme = self.cfg.get("preferences", "theme", default="cyberfire")
        hue = f"{c.active()}Hue: ON{c.CR}" if self.hue_enabled else "Hue: OFF"
        pi = ""
        if self.cfg.get("preferences", "enable_pi_temp", default=True):
            pi = get_pi_temp() or ""
        keys = "[A/D] Panel  [W/S] Navigate  [Enter] Read  [R] Refresh  [C] Theme  [F] Units  [T] Time  [X] Hue  [Q] Quit"
        return "\n".join([
            f"{c.border()}├{'─' * (W - 2)}┤{c.CR}",
            f"{c.border()}│{c.CR} {keys}  {theme}  {hue} {pi}{c.border()}│{c.CR}",
            f"{c.border()}╰{'─' * (W - 2)}╯{c.CR}",
        ])

    # -- panels -------------------------------------------------------------
    def panel_news(self, c) -> list:
        lines = [f"{c.header()}── NEWS ──{c.CR}  {self._news.get('total_unread', 0)} unread"]
        articles = self._news.get("articles", [])
        if not articles:
            lines.append("  No articles cached — press R after connecting, feeds load on refresh.")
        for i, a in enumerate(articles[:18]):
            mark = f"{c.active()}➔{c.CR}" if i == self.sel else " "
            dot = " " if a.get("viewed") else f"{c.hex('accent3')}●{c.CR}"
            title = a.get("display_title", a.get("title", ""))
            row = f" {mark} {c.hex('accent2')}{a.get('source', ''):<10}{c.CR} {title[:64]:<64} {rel_age(a.get('fetched_at', 0)):>3} {dot}"
            lines.append(row)
        return lines

    def panel_weather(self, c) -> list:
        w = self._weather
        lines = [f"{c.header()}── WEATHER ──{c.CR}"]
        if not w.get("ok"):
            lines.append("  Weather unavailable (offline, no cache).")
            return lines
        cur = w["current"]
        unit = w.get("unit_symbol", "")
        lines.append(f"  {cur['icon']} {cur['description']}   "
                     f"{c.hex('accent2')}{cur['temperature']:.0f}{unit}{c.CR}  "
                     f"feels {cur['feels_like']:.0f}{unit}  💧 {cur['humidity']}%  "
                     f"💨 {cur['wind_speed']} {w.get('wind_unit', 'km/h')} {cur['wind_direction']}  ☁ {cur['cloud_cover']}%")
        lines.append("")
        lines.append(f"  {c.hex('accent1')}24H{c.CR}  " + " ".join(
            f"{h['label']} {h['temperature']:.0f}{unit}" if h["temperature"] is not None else ""
            for h in w["hourly"][::3]))
        lines.append("")
        for d in w["daily"]:
            bar = _bar((d["max"] or 0) - (d["min"] or 0), 12, 0, 25)
            lines.append(f"  {d['label']:<3} {d['icon']} {d['min']:>4.0f}{unit} {bar} {d['max']:<4.0f}{unit}  💧{d['precip_probability']}%")
        return lines

    def panel_solar(self, c) -> list:
        s = self._solar
        lines = [f"{c.header()}── SOLAR ACTIVITY ──{c.CR}"]
        geo = s.get("geomagnetic") or {}
        wind = s.get("solar_wind") or {}
        kp = geo.get("kp_index")
        dv = lambda v: "--" if v is None else v
        lines.append(f"  Sunspot #   {_bar(s.get('sunspot_number') or 0, 15, 0, 250)} {dv(s.get('sunspot_number'))}")
        lines.append(f"  Solar Flux  {_bar(s.get('solar_flux') or 0, 15, 60, 250)} {dv(s.get('solar_flux'))}")
        lines.append(f"  Kp Index    {_bar(kp or 0, 15, 0, 9)} {kp if kp is not None else '--'}  {geo.get('label', '')}")
        lines.append(f"  A Index     {geo.get('a_index', '--')}    Aurora: {geo.get('aurora_probability', '--')}%")
        if wind:
            lines.append(f"  Solar Wind  {wind.get('speed', '--')} km/s   density {wind.get('density', '--')} p/cm³   Bz {wind.get('bz', '--')} nT")
        lines.append(f"  Active regions: {dv(s.get('active_regions'))}")
        fc = s.get("forecast") or {}
        if fc:
            lines.append("  Forecast: " + "  ".join(f"{d} Kp {v['kp_index']}" for d, v in list(fc.items())[:5]))
        return lines

    def panel_space(self, c) -> list:
        sp = self._space
        lines = [f"{c.header()}── SPACE ──{c.CR}"]
        sun = sp.get("sun_times", {})
        moon = sp.get("moon_data", {})
        def hm(v):
            return str(v)[11:16] if v else "--:--"
        lines.append(f"  ☀ Sunrise {hm(sun.get('sunrise') or sun.get('sunrise_utc'))}   Sunset {hm(sun.get('sunset') or sun.get('sunset_utc'))}")
        lines.append(f"  ☽ Moonrise {hm(sun.get('moonrise'))}   Moonset {hm(sun.get('moonset'))}")
        lines.append(f"  {moon.get('icon', '')} {moon.get('name', '')} — {moon.get('illumination', '--')}% lit")
        lines.append("")
        for p in sp.get("planets", []):
            vis = f"{c.active()}●{c.CR}" if p["visible"] else "○"
            lines.append(f"  {vis} {p['name']:<8} alt {p['altitude']:>6}°  az {p['azimuth']:>6}°")
        iss = sp.get("iss")
        if iss:
            lines.append(f"  🛰 ISS {'LIVE' if iss.get('live') else 'cached'} — lat {iss['latitude']}° lon {iss['longitude']}° alt {iss['altitude_km']} km")
        return lines

    def render_panel(self, c, idx=None) -> str:
        idx = self.panel if idx is None else idx
        fn = [self.panel_news, self.panel_weather, self.panel_solar, self.panel_space][idx]
        return "\n".join(fn(c))

    def render(self, all_panels=False) -> str:
        c = self.colors()
        out = [self.header(c)]
        if all_panels:
            for i in range(4):
                out.append(self.render_panel(c, i))
                out.append("")
        else:
            out.append(self.render_panel(c))
        out.append(self.footer(c))
        return "\n".join(out)

    # -- hue ------------------------------------------------------------------
    def trigger_hue(self):
        if not self.hue_enabled or not self.cfg.hue_configured():
            return
        client = HueClient(self.cfg.hue_bridge_ip(), self.cfg.hue_api_key(),
                           lights=self.cfg.get("hue", "lights", default=[1, 6]))
        code = (self._weather.get("current") or {}).get("weather_code")
        kp = (self._solar.get("geomagnetic") or {}).get("kp_index")
        theme = themes.get_theme(self.cfg.get("preferences", "theme", default="cyberfire"))
        client.set_all(condition_payload(code, kp, theme))

    # -- article reader ---------------------------------------------------------
    def read_article(self, article, inp):
        self.service.mark_read(article["link"])
        paragraphs = self.service.get_article(article["link"])["paragraphs"]
        c = self.colors()
        idx = 0
        while True:
            try:
                h, w = __import__("os").get_terminal_size().lines, __import__("os").get_terminal_size().columns
            except Exception:
                h, w = 24, 80
            w, cw = max(w, 40), max(min(w, W) - 4, 20)
            page = max(h - 10, 4)
            lines = []
            for p in paragraphs:
                lines += textwrap.wrap(p, width=cw) + [""]
            max_idx = max(0, len(lines) - page)
            out = [f"{c.border()}╭{'─' * (w - 2)}╮{c.CR}",
                   f"{c.border()}│{c.CR} {c.header()}{article.get('display_title', '')[:w - 6]}{c.CR}",
                   f"{c.border()}├{'─' * (w - 2)}┤{c.CR}"]
            for line in lines[idx:idx + page]:
                out.append(f"{c.border()}│{c.CR} {vpad(line, cw)} {c.border()}│{c.CR}")
            out.append(f"{c.border()}├{'─' * (w - 2)}┤{c.CR}")
            out.append(f"{c.border()}│{c.CR} [W/S] Scroll  [O] Browser  [Q] Back{c.border()}│{c.CR}")
            out.append(f"{c.border()}╰{'─' * (w - 2)}╯{c.CR}")
            sys.stdout.write("\033[H" + "\n".join(out) + "\033[J")
            sys.stdout.flush()
            cmd = inp.read(0.2)
            if cmd in ("w", "up", "k"):
                idx = max(0, idx - 2)
            elif cmd in ("s", "down", "j"):
                idx = min(max_idx, idx + 2)
            elif cmd == "o":
                open_in_browser(article["link"])
            elif cmd in ("q", "esc"):
                break

    # -- main loop ----------------------------------------------------------------
    def handle_input(self, cmd, inp) -> bool:
        """Return False to quit."""
        if cmd is None:
            return True
        if cmd in ("q",):
            return False
        if cmd in ("a",):
            self.panel = (self.panel - 1) % 4
            self.sel = 0
        elif cmd in ("d",):
            self.panel = (self.panel + 1) % 4
            self.sel = 0
        elif cmd in ("w", "up", "k"):
            self.sel = max(0, self.sel - 1)
        elif cmd in ("s", "down", "j"):
            count = len(self._news.get("articles", [])) if self.panel == 0 else 3
            self.sel = min(count - 1, self.sel + 1) if count else 0
        elif cmd in ("r",):
            if self.panel == 0:
                self.service.refresh_news()
            self.refresh()
            self.trigger_hue()
        elif cmd in ("c",):
            cur = self.cfg.get("preferences", "theme", default="cyberfire")
            self.cfg.set("preferences", "theme", value=themes.next_theme(cur))
        elif cmd in ("f",):
            cur = self.cfg.get("preferences", "units", default="metric")
            self.cfg.set("preferences", "units", value="imperial" if cur == "metric" else "metric")
            self.refresh()
        elif cmd in ("t",):
            cur = self.cfg.get("preferences", "time_format", default="24h")
            self.cfg.set("preferences", "time_format", value="12h" if cur == "24h" else "24h")
        elif cmd in ("x",):
            self.hue_enabled = not self.hue_enabled
            self.cfg.set("preferences", "enable_hue", value=self.hue_enabled)
            self.trigger_hue()
        elif cmd in ("enter", " ") and self.panel == 0:
            articles = self._news.get("articles", [])
            if articles and self.sel < len(articles):
                self.read_article(articles[self.sel], inp)
        elif cmd == "o" and self.panel == 0:
            articles = self._news.get("articles", [])
            if articles and self.sel < len(articles):
                open_in_browser(articles[self.sel]["link"])
        elif cmd == "m" and self.panel == 0:
            self.service.mark_all_read()
            self._news = self.service.get_news(limit=200)
        return True

    def run(self):
        inp = InputHandler(bool(self.cfg.get("preferences", "enable_mouse", default=True)))
        sys.stdout.write("\033[?25l")
        try:
            last = ""
            while True:
                frame = "\033[H" + self.render() + "\033[J"
                if frame != last:
                    sys.stdout.write(frame)
                    sys.stdout.flush()
                    last = frame
                cmd = inp.read(0.15)
                if not self.handle_input(cmd, inp):
                    break
        finally:
            sys.stdout.write("\033[?25h\033[0m\n")
            sys.stdout.flush()
