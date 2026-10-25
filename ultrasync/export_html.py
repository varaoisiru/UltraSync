"""Static HTML snapshot export (`--export-html`).

Adapts Ultrareader's original index.html web face — clock, weather
strip, source buttons, article list — to the unified theme engine and
bakes in all four panels' current data as a single self-contained file.
"""
import html
from datetime import datetime

from . import themes


def render_snapshot(service, theme_name: str) -> str:
    t = themes.get_theme(theme_name)
    wx = service.get_weather()
    solar = service.get_solar()
    space = service.get_space()
    news = service.get_news(limit=40)
    loc = service.location()

    cur = wx.get("current", {}) if wx.get("ok") else {}
    weather_line = (
        f"{loc.get('city', '')}: {cur.get('description', '—')} "
        f"{cur.get('temperature', '--')}{wx.get('unit_symbol', '')}"
        if wx.get("ok") else "Weather offline")

    articles = "\n".join(
        f'<a href="{html.escape(a["link"])}" target="_blank" rel="noopener">'
        f'[{html.escape(a["source"])}] {html.escape(a["display_title"])}</a>'
        for a in news["articles"]) or "<p>No articles cached.</p>"

    geo = solar.get("geomagnetic") or {}
    moon = space.get("moon_data", {})
    planets = "".join(
        f"<tr><td>{p['name']}</td><td>{p['altitude']}°</td>"
        f"<td>{'visible' if p['visible'] else 'below horizon'}</td></tr>"
        for p in space.get("planets", []))
    iss = space.get("iss") or {}

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>UltraSync — snapshot</title>
<style>
body{{background:{t['bg']};color:{t['primary']};font-family:monospace;margin:0;padding:12px}}
h1{{color:{t['accent1']};margin:6px 0;font-size:22px;letter-spacing:3px}}
h2{{color:{t['accent1']};font-size:15px;letter-spacing:2px;border-bottom:1px solid {t['dim']};padding-bottom:4px}}
.clock{{font-size:34px;color:{t['accent2']};margin:8px 0;text-align:center}}
.weather{{color:#fff;margin:8px 0;border:1px solid {t['dim']};padding:8px;text-align:center}}
a{{color:{t['accent2']};text-decoration:none;display:block;padding:6px 0;border-bottom:1px solid #222;font-size:14px}}
a:active{{color:#fff}}
.section{{margin:14px 0}}
table{{border-collapse:collapse}} td{{padding:3px 10px 3px 0}}
.dim{{opacity:.65;font-size:12px}}
</style>
</head>
<body>
<h1>ULTRASYNC</h1>
<div class="clock" id="clock">--:--:--</div>
<div class="weather">{html.escape(weather_line)}</div>

<div class="section"><h2>NEWS</h2>
{articles}
</div>

<div class="section"><h2>SOLAR</h2>
<table>
<tr><td>Sunspot #</td><td>{solar.get('sunspot_number', '—')}</td></tr>
<tr><td>Solar flux</td><td>{solar.get('solar_flux', '—')}</td></tr>
<tr><td>Kp index</td><td>{geo.get('kp_index', '—')} ({html.escape(str(geo.get('label', '')))})</td></tr>
<tr><td>Aurora probability</td><td>{geo.get('aurora_probability', '—')}%</td></tr>
</table></div>

<div class="section"><h2>SPACE</h2>
<p>{moon.get('icon', '')} {html.escape(str(moon.get('name', '')))} — {moon.get('illumination', '—')}% lit</p>
<table>{planets}</table>
<p class="dim">ISS: lat {iss.get('latitude', '—')}°, lon {iss.get('longitude', '—')}°, alt {iss.get('altitude_km', '—')} km</p>
</div>

<p class="dim">UltraSync 2.0.0 snapshot · theme {html.escape(t['name'])} · generated {datetime.now().isoformat(timespec='seconds')}</p>
<script>
function tick(){{let d=new Date();let h=d.getHours();let m=String(d.getMinutes()).padStart(2,'0');let s=String(d.getSeconds()).padStart(2,'0');let ap=h>=12?'PM':'AM';h=h%12||12;document.getElementById('clock').textContent=h+':'+m+':'+s+' '+ap;}}
setInterval(tick,1000);tick();
</script>
</body>
</html>
"""
