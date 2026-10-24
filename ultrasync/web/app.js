/* UltraSync GUI — vanilla JS, no build step.
   Every panel is wired to the FastAPI JSON API; on fetch failure the
   last good data stays on screen and the status pill shows OFFLINE. */
"use strict";

const $ = (id) => document.getElementById(id);
const state = {
  theme: null, themes: {}, units: "metric",
  sourceFilter: null, lastData: {}, hueConfigured: false,
};

async function api(path, opts) {
  const r = await fetch(path, opts);
  if (!r.ok) throw new Error(path + " -> " + r.status);
  return r.json();
}
function post(path, body) {
  return api(path, { method: "POST", headers: { "Content-Type": "application/json" },
                     body: JSON.stringify(body || {}) });
}
function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
function relAge(ts) {
  if (!ts) return "";
  const s = Math.floor(Date.now() / 1000) - ts;
  if (s < 60) return "now"; if (s < 3600) return Math.floor(s / 60) + "m";
  if (s < 86400) return Math.floor(s / 3600) + "h"; return Math.floor(s / 86400) + "d";
}
function setBadge(id, data) {
  const b = $(id);
  if (!data) { b.textContent = "OFFLINE"; b.classList.add("stale"); return; }
  if (data.stale) { b.textContent = "CACHED " + (data.age_seconds != null ? relAge(Math.floor(Date.now()/1000) - data.age_seconds) + " old" : ""); b.classList.add("stale"); }
  else { b.textContent = "LIVE"; b.classList.remove("stale"); }
}
function setPill(mode) {
  const p = $("statusPill");
  p.className = "statuspill " + mode;
  p.textContent = mode.toUpperCase();
}
function fitCanvas(cv) {
  const dpr = window.devicePixelRatio || 1;
  const w = cv.clientWidth || cv.parentElement.clientWidth || 300;
  const h = parseInt(cv.getAttribute("height"), 10) || 90;
  cv.width = w * dpr; cv.height = h * dpr;
  cv.style.height = h + "px";
  const ctx = cv.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { ctx, w, h };
}

/* ---------------- theme ---------------- */
function applyTheme(name) {
  const t = state.themes[name];
  if (!t) return;
  state.theme = name;
  const root = document.documentElement.style;
  for (const k of ["bg", "primary", "accent1", "accent2", "accent3", "dim"]) root.setProperty("--" + k, t[k]);
  document.querySelectorAll(".swatch").forEach((s) => s.classList.toggle("active", s.dataset.theme === name));
  drawAllCharts();
}
async function loadThemes() {
  const data = await api("/api/themes");
  state.themes = data.themes;
  const box = $("themes");
  box.innerHTML = "";
  for (const [name, t] of Object.entries(data.themes)) {
    const b = document.createElement("button");
    b.className = "swatch"; b.dataset.theme = name; b.title = t.name;
    b.style.background = `linear-gradient(135deg, ${t.primary} 0 55%, ${t.accent1} 55% 100%)`;
    b.addEventListener("click", async () => { applyTheme(name); await post("/api/theme", { name }); });
    box.appendChild(b);
  }
  applyTheme(data.active);
}

/* ---------------- clock ---------------- */
function tickClock() {
  const d = new Date();
  $("clock").textContent = d.toLocaleTimeString();
}
setInterval(tickClock, 1000); tickClock();

/* ---------------- news ---------------- */
function renderNews(data) {
  state.lastData.news = data;
  setBadge("newsBadge", { stale: false });
  const loc = $("articles");
  loc.innerHTML = "";
  $("newsEmpty").hidden = data.articles.length > 0;
  const chips = $("sourceChips");
  chips.innerHTML = "";
  const mkChip = (label, src) => {
    const c = document.createElement("button");
    c.className = "chip" + (state.sourceFilter === src ? " active" : "");
    c.textContent = label;
    c.addEventListener("click", () => { state.sourceFilter = src; refreshNews(); });
    chips.appendChild(c);
  };
  mkChip("ALL" + (data.total_unread ? ` (${data.total_unread})` : ""), null);
  for (const s of data.sources) mkChip(s, s);
  for (const a of data.articles) {
    const li = document.createElement("li");
    if (a.viewed) li.className = "viewed";
    const src = document.createElement("span"); src.className = "src"; src.textContent = a.source;
    const ttl = document.createElement("span"); ttl.className = "ttl"; ttl.textContent = a.display_title;
    const age = document.createElement("span"); age.className = "age"; age.textContent = relAge(a.fetched_at);
    li.append(src, ttl, age);
    if (!a.viewed) { const d = document.createElement("span"); d.className = "dot"; d.textContent = "●"; li.appendChild(d); }
    li.addEventListener("click", () => openReader(a));
    loc.appendChild(li);
  }
}
async function refreshNews() {
  try {
    const q = new URLSearchParams();
    if (state.sourceFilter) q.set("source", state.sourceFilter);
    const s = $("newsSearch").value.trim(); if (s) q.set("search", s);
    renderNews(await api("/api/news?" + q.toString()));
  } catch (e) { setBadge("newsBadge", null); setPill("offline"); }
}
async function openReader(article) {
  const r = $("reader");
  $("readerTitle").textContent = article.display_title;
  $("readerLink").href = article.link;
  $("readerBody").innerHTML = "<p>Loading article…</p>";
  r.hidden = false;
  try {
    const data = await api("/api/news/article?link=" + encodeURIComponent(article.link));
    const body = $("readerBody");
    body.innerHTML = "";
    for (const p of data.paragraphs) {
      const el = document.createElement("p"); el.textContent = p; body.appendChild(el);
    }
    article.viewed = 1; refreshNews();
  } catch (e) {
    $("readerBody").innerHTML = "<p>Could not load this article (offline?). Use “Open original”.</p>";
  }
}
$("readerClose").addEventListener("click", () => { $("reader").hidden = true; });
document.addEventListener("keydown", (e) => { if (e.key === "q" || e.key === "Escape") $("reader").hidden = true; });
$("newsRefresh").addEventListener("click", async (ev) => {
  ev.target.disabled = true;
  try { renderNews(await post("/api/news/refresh")); } catch (e) { setBadge("newsBadge", null); }
  ev.target.disabled = false;
});
$("newsReadAll").addEventListener("click", async () => {
  await post("/api/news/read-all", state.sourceFilter ? { source: state.sourceFilter } : {});
  refreshNews();
});
let searchTimer = null;
$("newsSearch").addEventListener("input", () => { clearTimeout(searchTimer); searchTimer = setTimeout(refreshNews, 350); });

/* ---------------- weather ---------------- */
function drawTempChart() {
  const data = state.lastData.weather;
  const cv = $("tempChart");
  if (!data || !data.hourly || !data.hourly.length) return;
  const { ctx, w, h } = fitCanvas(cv);
  const vals = data.hourly.map((x) => x.temperature).filter((v) => v != null);
  if (!vals.length) return;
  const min = Math.min(...vals), max = Math.max(...vals), span = (max - min) || 1;
  ctx.clearRect(0, 0, w, h);
  ctx.strokeStyle = cssVar("--dim"); ctx.beginPath(); ctx.moveTo(0, h - 14); ctx.lineTo(w, h - 14); ctx.stroke();
  ctx.strokeStyle = cssVar("--accent2"); ctx.lineWidth = 2; ctx.beginPath();
  data.hourly.forEach((pt, i) => {
    const x = (i / (data.hourly.length - 1)) * (w - 8) + 4;
    const y = h - 18 - ((pt.temperature - min) / span) * (h - 34);
    i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
  });
  ctx.stroke();
  ctx.fillStyle = cssVar("--primary"); ctx.font = "10px monospace";
  ctx.fillText(max.toFixed(0) + (data.unit_symbol || ""), 4, 12);
  ctx.fillText(min.toFixed(0) + (data.unit_symbol || ""), 4, h - 16);
  ctx.fillStyle = cssVar("--accent1");
  data.hourly.forEach((pt, i) => { if (i % 6 === 0) ctx.fillText(pt.label, (i / (data.hourly.length - 1)) * (w - 30) + 2, h - 2); });
}
function renderWeather(data) {
  state.lastData.weather = data;
  setBadge("wxBadge", data.ok ? data : null);
  $("wxEmpty").hidden = !!data.ok;
  if (!data.ok) return;
  const c = data.current;
  $("wxIcon").textContent = c.icon || "?";
  $("wxTemp").textContent = c.temperature != null ? c.temperature.toFixed(0) + data.unit_symbol : "--";
  $("wxDesc").textContent = c.description || "—";
  $("wxFeels").textContent = c.feels_like != null ? "feels " + c.feels_like.toFixed(0) + data.unit_symbol : "";
  const stats = [
    ["Humidity", c.humidity != null ? c.humidity + "%" : "--"],
    ["Wind", (c.wind_speed ?? "--") + " km/h " + (c.wind_direction || "")],
    ["Clouds", c.cloud_cover != null ? c.cloud_cover + "%" : "--"],
    ["Precip", (c.precipitation ?? 0) + " mm"],
  ];
  $("wxStats").innerHTML = stats.map(([k, v]) => `<span class="dim">${k}</span><span>${v}</span>`).join("");
  const days = $("wxDays");
  days.innerHTML = "";
  for (const d of data.daily) {
    const el = document.createElement("div");
    el.className = "day";
    el.innerHTML = `<b>${d.label}</b><span class="ic">${d.icon}</span>` +
      `<span class="hi">${d.max != null ? d.max.toFixed(0) : "--"}°</span> / ${d.min != null ? d.min.toFixed(0) : "--"}°` +
      `<br>💧${d.precip_probability ?? "--"}%`;
    days.appendChild(el);
  }
  drawTempChart();
}
async function refreshWeather() {
  try { renderWeather(await api("/api/weather")); }
  catch (e) { setBadge("wxBadge", null); setPill("offline"); }
}

/* ---------------- solar ---------------- */
function drawGauge(cvId, value, max, colorKey) {
  const cv = $(cvId);
  const ctx = cv.getContext("2d");
  const w = cv.width, h = cv.height;
  ctx.clearRect(0, 0, w, h);
  const cx = w / 2, cy = h - 8, r = Math.min(w / 2 - 6, h - 16);
  ctx.lineWidth = 9;
  ctx.strokeStyle = "rgba(255,255,255,0.12)";
  ctx.beginPath(); ctx.arc(cx, cy, r, Math.PI, 2 * Math.PI); ctx.stroke();
  if (value == null) return;
  const frac = Math.max(0, Math.min(1, value / max));
  ctx.strokeStyle = cssVar(colorKey);
  ctx.beginPath(); ctx.arc(cx, cy, r, Math.PI, Math.PI + frac * Math.PI); ctx.stroke();
}
function drawKpChart() {
  const data = state.lastData.solar;
  const cv = $("kpChart");
  if (!data || !data.forecast) return;
  const entries = Object.entries(data.forecast).slice(0, 12);
  if (!entries.length) return;
  const { ctx, w, h } = fitCanvas(cv);
  ctx.clearRect(0, 0, w, h);
  const bw = w / entries.length;
  entries.forEach(([day, f], i) => {
    const kp = parseFloat(f.kp_index) || 0;
    const bh = (kp / 9) * (h - 20);
    ctx.fillStyle = kp >= 5 ? cssVar("--accent3") : kp >= 4 ? cssVar("--accent2") : cssVar("--primary");
    ctx.fillRect(i * bw + 3, h - 12 - bh, bw - 6, bh);
    ctx.fillStyle = cssVar("--primary"); ctx.font = "9px monospace";
    ctx.fillText(day.slice(5), i * bw + 3, h - 1);
  });
  ctx.fillStyle = cssVar("--accent1"); ctx.font = "10px monospace";
  ctx.fillText("Kp forecast", 2, 10);
}
function renderSolar(data) {
  state.lastData.solar = data;
  setBadge("solarBadge", data.ok ? data : null);
  $("solarEmpty").hidden = !!data.ok;
  const geo = data.geomagnetic || {};
  const wind = data.solar_wind || {};
  $("valSunspot").textContent = data.sunspot_number ?? "—";
  $("valFlux").textContent = data.solar_flux ?? "—";
  $("valKp").textContent = geo.kp_index ?? "—";
  drawGauge("gaugeSunspot", data.sunspot_number, 250, "--accent1");
  drawGauge("gaugeFlux", data.solar_flux, 250, "--accent2");
  drawGauge("gaugeKp", geo.kp_index, 9, geo.kp_index >= 5 ? "--accent3" : "--primary");
  const rows = [
    ["Condition", geo.label || "—"],
    ["A Index", geo.a_index ?? "—"],
    ["Aurora probability", (geo.aurora_probability ?? "—") + (geo.aurora_probability != null ? "%" : "")],
    ["Solar wind", wind.speed != null ? wind.speed + " km/s" : "—"],
    ["Wind density", wind.density != null ? wind.density + " p/cm³" : "—"],
    ["Bz (GSM)", wind.bz != null ? wind.bz + " nT" : "—"],
    ["Active regions", data.active_regions ?? "—"],
  ];
  $("solarKv").innerHTML = rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("");
  drawKpChart();
}
async function refreshSolar() {
  try { renderSolar(await api("/api/solar")); }
  catch (e) { setBadge("solarBadge", null); setPill("offline"); }
}

/* ---------------- space ---------------- */
function drawMoon(phase) {
  const cv = $("moonCanvas");
  const ctx = cv.getContext("2d");
  const w = cv.width, h = cv.height, cx = w / 2, cy = h / 2, r = Math.min(w, h) / 2 - 4;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "rgba(255,255,255,0.10)";
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill();
  // lit portion: terminator ellipse sweeps with phase (waxing lit on right)
  ctx.fillStyle = cssVar("--accent2");
  ctx.beginPath();
  const k = Math.cos(2 * Math.PI * phase);
  if (phase <= 0.5) {
    ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2, false);
    ctx.ellipse(cx, cy, Math.abs(k) * r, r, 0, Math.PI / 2, -Math.PI / 2, k > 0);
  } else {
    ctx.arc(cx, cy, r, Math.PI / 2, 3 * Math.PI / 2, false);
    ctx.ellipse(cx, cy, Math.abs(k) * r, r, 0, -Math.PI / 2, Math.PI / 2, k > 0);
  }
  ctx.fill();
  ctx.strokeStyle = cssVar("--dim");
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke();
}
function fmtT(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return isNaN(d) ? String(iso).slice(11, 16) : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
function renderSpace(data) {
  state.lastData.space = data;
  setBadge("spaceBadge", { stale: false });
  const moon = data.moon_data || {};
  const sun = data.sun_times || {};
  $("moonName").textContent = moon.name || "—";
  $("moonIllum").textContent = moon.illumination != null ? moon.illumination + "% lit" : "";
  drawMoon(moon.phase || 0);
  const rows = [
    ["☀ Sunrise", fmtT(sun.sunrise || sun.sunrise_utc)],
    ["☀ Sunset", fmtT(sun.sunset || sun.sunset_utc)],
    ["☽ Moonrise", fmtT(sun.moonrise)],
    ["☽ Moonset", fmtT(sun.moonset)],
  ];
  $("spaceKv").innerHTML = rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("");
  const tbl = $("planets");
  tbl.innerHTML = "<tr><th>Planet</th><th>Altitude</th><th>Azimuth</th><th></th></tr>" +
    (data.planets || []).map((p) =>
      `<tr><td>${p.name}</td><td>${p.altitude}°</td><td>${p.azimuth}°</td>` +
      `<td class="${p.visible ? "vis-yes" : "vis-no"}">${p.visible ? "● visible" : "○ below horizon"}</td></tr>`).join("");
  const iss = data.iss;
  $("issBox").innerHTML = iss
    ? `🛰 <b>ISS</b> ${iss.live ? "LIVE" : "cached"} — lat ${iss.latitude}°, lon ${iss.longitude}°, alt ${iss.altitude_km} km, ${iss.velocity_kmh} km/h`
    : `🛰 <b>ISS</b> — ${data.iss_passes ? "passes: " + data.iss_passes.time + ", duration " + data.iss_passes.duration : "position unavailable offline"}`;
}
async function refreshSpace() {
  try { renderSpace(await api("/api/space")); }
  catch (e) { setBadge("spaceBadge", null); setPill("offline"); }
}

/* ---------------- hue ---------------- */
function renderHue(data) {
  state.hueConfigured = data.configured;
  setBadge("hueBadge", { stale: false });
  $("hueBadge").textContent = data.configured ? "BRIDGE OK" : "NOT CONFIGURED";
  $("hueEmpty").hidden = data.configured;
  $("hueSyncToggle").checked = !!data.sync_conditions;
  const box = $("hueLights");
  box.innerHTML = "";
  for (const l of data.lights) {
    const el = document.createElement("div");
    el.className = "light";
    const name = document.createElement("div");
    name.className = "lname";
    name.textContent = `💡 ${l.name} ${l.reachable ? "" : "(unreachable)"}`;
    const tog = document.createElement("button");
    tog.className = "chipbtn"; tog.textContent = l.on ? "ON" : "OFF";
    tog.addEventListener("click", async () => { await post("/api/hue/light", { id: l.id, on: !l.on }); refreshHue(); });
    const bri = document.createElement("input");
    bri.type = "range"; bri.min = 1; bri.max = 254; bri.value = l.bri || 200;
    bri.addEventListener("change", async () => { await post("/api/hue/light", { id: l.id, on: true, bri: parseInt(bri.value, 10) }); });
    el.append(name, tog, bri);
    box.appendChild(el);
  }
  $("fxNow").textContent = data.fx && data.fx.playing ? "playing: " + data.fx.playing.name : "";
  if (!$("hueBridge").value && data.bridge_ip) $("hueBridge").value = data.bridge_ip;
  if (!$("hueLightIds").value && data.configured_light_ids) $("hueLightIds").value = data.configured_light_ids.join(", ");
}
async function refreshHue() {
  try { renderHue(await api("/api/hue/status")); }
  catch (e) { setBadge("hueBadge", null); }
}
async function loadFx() {
  try {
    const data = await api("/api/hue/fx");
    const sel = $("fxSelect");
    sel.innerHTML = "";
    for (const fx of data.effects) {
      const o = document.createElement("option");
      o.value = fx.index; o.textContent = `${fx.index + 1}. ${fx.name} — ${fx.description}`;
      sel.appendChild(o);
    }
  } catch (e) { /* hue endpoints always exist; ignore transient */ }
}
$("fxPlay").addEventListener("click", async () => {
  if (!state.hueConfigured) { alert("Configure the Hue bridge first."); return; }
  await post("/api/hue/fx", { index: parseInt($("fxSelect").value, 10) });
  refreshHue();
});
$("fxStop").addEventListener("click", async () => { await post("/api/hue/fx", { action: "stop" }); refreshHue(); });
$("hueSyncToggle").addEventListener("change", async (ev) => {
  const r = await post("/api/hue/sync", { enabled: ev.target.checked });
  if (!r.configured) { ev.target.checked = false; }
  refreshHue();
});
$("hueSave").addEventListener("click", async () => {
  const ids = $("hueLightIds").value.split(",").map((s) => parseInt(s.trim(), 10)).filter((n) => !isNaN(n));
  const body = { hue: { bridge_ip: $("hueBridge").value.trim() || null, lights: ids.length ? ids : [1, 6] } };
  const key = $("hueKey").value.trim();
  if (key) body.hue.api_key = key;
  await post("/api/config", body);
  $("hueKey").value = "";
  $("hueSaveMsg").textContent = "saved";
  setTimeout(() => { $("hueSaveMsg").textContent = ""; }, 2500);
  refreshHue();
});

/* ---------------- units + status ---------------- */
$("unitsBtn").addEventListener("click", async () => {
  const next = state.units === "metric" ? "imperial" : "metric";
  const cfg = await post("/api/config", { preferences: { units: next } });
  state.units = cfg.preferences.units;
  $("unitsBtn").textContent = state.units === "metric" ? "°C" : "°F";
  refreshWeather();
});
async function refreshStatus() {
  try {
    const s = await api("/api/status");
    $("location").textContent = s.location ? `${s.location.city || ""} · ${s.location.latitude?.toFixed(2)}, ${s.location.longitude?.toFixed(2)}` : "";
    $("updatedAt").textContent = "updated " + new Date().toLocaleTimeString();
    setPill(s.weather && s.weather.stale ? "cached" : "live");
    if (s.theme && s.theme !== state.theme) applyTheme(s.theme);
  } catch (e) { setPill("offline"); }
}

function drawAllCharts() { drawTempChart(); drawKpChart(); if (state.lastData.space) drawMoon(state.lastData.space.moon_data.phase || 0); }
window.addEventListener("resize", drawAllCharts);

/* ---------------- boot + polling ---------------- */
(async function boot() {
  try {
    const cfg = await api("/api/config");
    state.units = cfg.preferences.units;
    $("unitsBtn").textContent = state.units === "metric" ? "°C" : "°F";
  } catch (e) { /* config endpoint down — defaults apply */ }
  try { await loadThemes(); } catch (e) { setPill("offline"); }
  await Promise.allSettled([refreshStatus(), refreshNews(), refreshWeather(), refreshSolar(), refreshSpace(), refreshHue(), loadFx()]);
  setInterval(refreshStatus, 60000);
  setInterval(refreshWeather, 60000);
  setInterval(refreshSolar, 60000);
  setInterval(refreshSpace, 30000);
  setInterval(refreshHue, 30000);
  setInterval(refreshNews, 300000);
})();
