"""FastAPI backend — serves the UltraSync web GUI and JSON API.

The GUI and the terminal UI share the same DataService; this module is
only HTTP plumbing plus Hue control endpoints. Credentials are never
returned by any endpoint (config responses carry an api_key_set flag).
"""
import sys
import threading
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from . import __version__, themes
from .briefing import assemble_briefing, render_briefing_png
from .circadian import circadian_from_space
from .config import Config
from .hue import HueClient, HueFXPlayer, condition_payload
from .service import DataService


def _web_dir() -> Path:
    if getattr(sys, "frozen", False):  # PyInstaller bundle
        return Path(sys._MEIPASS) / "ultrasync" / "web"
    return Path(__file__).parent / "web"


class HueManager:
    """Owns the Hue client + FX player; rebuilds when config changes."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self._lock = threading.Lock()
        self._build()

    def _build(self):
        self.client = HueClient(self.cfg.hue_bridge_ip(), self.cfg.hue_api_key(),
                                lights=self.cfg.get("hue", "lights", default=[1, 6]))
        self.player = HueFXPlayer(self.client)

    def refresh(self):
        with self._lock:
            self.player.stop()
            self._build()

    def status(self) -> dict:
        lights = self.client.get_lights() if self.client.configured else {}
        return {
            "configured": self.client.configured,
            "bridge_ip": self.client.bridge_ip,
            "api_key_set": bool(self.cfg.hue_api_key()),
            "lights": [lights[k] for k in sorted(lights, key=int)] if lights else [],
            "configured_light_ids": self.client.lights,
            "sync_conditions": bool(self.cfg.get("hue", "sync_conditions", default=False)),
            "sync_mode": self.cfg.get("hue", "sync_mode", default="conditions"),
            "fx": self.player.status(),
        }

    def sync_now(self, service: DataService) -> dict:
        """Push the active sync engine's payload to all configured lights.

        Mode comes from config hue.sync_mode: "conditions" (weather/Kp,
        the v1 engine) or "circadian" (sun-position engine, v2)."""
        if self.cfg.get("hue", "sync_mode", default="conditions") == "circadian":
            result = self.circadian_now(service)
            if result is not None:
                return result
            # sun times unavailable — fall through to condition sync
        weather = service.get_weather()
        solar = service.get_solar()
        code = (weather.get("current") or {}).get("weather_code")
        kp = (solar.get("geomagnetic") or {}).get("kp_index")
        theme = themes.get_theme(self.cfg.get("preferences", "theme", default="cyberfire"))
        payload = condition_payload(code, kp, theme)
        applied = self.client.set_all(payload) if self.client.configured else 0
        return {"applied_to": applied, "payload": payload}

    def circadian_now(self, service: DataService):
        """Compute the circadian state and push it (None if no sun times)."""
        state = circadian_from_space(service.get_space())
        if state is None:
            return None
        applied = self.client.set_all(state["payload"]) if self.client.configured else 0
        return {"applied_to": applied, **state}


def create_app(service: DataService = None, cfg: Config = None) -> FastAPI:
    cfg = cfg or (service.cfg if service else Config())
    service = service or DataService(cfg)
    hue_mgr = HueManager(cfg)

    app = FastAPI(title="UltraSync", version=__version__)
    app.state.service = service
    app.state.cfg = cfg
    app.state.hue = hue_mgr

    web = _web_dir()
    if web.exists():
        app.mount("/static", StaticFiles(directory=str(web)), name="static")

    @app.get("/")
    def index():
        return FileResponse(str(web / "index.html"))

    # -- status / config ---------------------------------------------------
    @app.get("/api/status")
    def status():
        return service.status()

    @app.get("/api/config")
    def get_config():
        return cfg.public_dict()

    @app.post("/api/config")
    async def post_config(req: Request):
        body = await req.json()
        prefs = body.get("preferences", {})
        for key in ("units", "time_format", "theme"):
            if key in prefs:
                cfg.set("preferences", key, value=prefs[key])
        loc = body.get("location", {})
        for key in ("auto_ip", "latitude", "longitude", "city", "timezone"):
            if key in loc:
                cfg.set("location", key, value=loc[key])
        hue = body.get("hue", {})
        for key in ("bridge_ip", "lights", "sync_conditions", "sync_mode"):
            if key in hue:
                cfg.set("hue", key, value=hue[key])
        if hue.get("api_key"):  # accepted, stored, never echoed back
            cfg.set("hue", "api_key", value=hue["api_key"])
        if loc:
            service._location = None
        hue_mgr.refresh()
        return cfg.public_dict()

    @app.get("/api/themes")
    def get_themes():
        return {"active": cfg.get("preferences", "theme", default="cyberfire"),
                "themes": themes.THEMES}

    @app.post("/api/theme")
    async def post_theme(req: Request):
        body = await req.json()
        name = body.get("name")
        if name in themes.THEMES:
            cfg.set("preferences", "theme", value=name)
            return {"active": name}
        return JSONResponse({"error": "unknown theme"}, status_code=400)

    # -- data panels ---------------------------------------------------------
    @app.get("/api/news")
    def news(source: str = None, search: str = "", limit: int = 60):
        return service.get_news(source=source, search=search, limit=limit)

    @app.post("/api/news/refresh")
    def news_refresh():
        count = service.refresh_news()
        return {"fetched": count, **service.get_news()}

    @app.post("/api/news/read")
    async def news_read(req: Request):
        body = await req.json()
        if body.get("link"):
            service.mark_read(body["link"])
        return {"ok": True, "unread": service.cache.count_unread()}

    @app.post("/api/news/read-all")
    async def news_read_all(req: Request):
        body = await req.json() if req.headers.get("content-length") else {}
        service.mark_all_read(body.get("source"))
        return {"ok": True, "unread": service.cache.count_unread()}

    @app.get("/api/news/article")
    def news_article(link: str):
        return service.get_article(link)

    @app.get("/api/weather")
    def weather():
        return service.get_weather()

    @app.get("/api/solar")
    def solar():
        return service.get_solar()

    @app.get("/api/space")
    def space():
        return service.get_space()

    # -- briefing card (2.0) --------------------------------------------
    @app.get("/api/briefing")
    def briefing():
        return assemble_briefing(service.get_weather(), service.get_solar(),
                                 service.get_news(limit=5))

    @app.get("/api/briefing.png")
    def briefing_png():
        data = assemble_briefing(service.get_weather(), service.get_solar(),
                                 service.get_news(limit=5))
        theme = themes.get_theme(cfg.get("preferences", "theme", default="cyberfire"))
        png = render_briefing_png(data, theme)
        if png is None:
            return JSONResponse(
                {"error": "Pillow is not installed — briefing card rendering "
                          "unavailable, JSON briefing still works",
                 "briefing": data}, status_code=501)
        return Response(png, media_type="image/png")

    # -- hue ------------------------------------------------------------------
    @app.get("/api/hue/status")
    def hue_status():
        return hue_mgr.status()

    @app.post("/api/hue/light")
    async def hue_light(req: Request):
        body = await req.json()
        if not hue_mgr.client.configured:
            return JSONResponse({"error": "hue not configured"}, status_code=409)
        payload = {k: body[k] for k in ("on", "bri", "hue", "sat", "transitiontime")
                   if k in body}
        ok = hue_mgr.client.set_state(int(body["id"]), payload)
        return {"ok": ok}

    @app.post("/api/hue/all")
    async def hue_all(req: Request):
        body = await req.json()
        if not hue_mgr.client.configured:
            return JSONResponse({"error": "hue not configured"}, status_code=409)
        payload = {k: body[k] for k in ("on", "bri", "hue", "sat", "transitiontime")
                   if k in body}
        return {"applied_to": hue_mgr.client.set_all(payload)}

    @app.get("/api/hue/fx")
    def hue_fx_list():
        return {"effects": hue_mgr.player.list_effects()}

    @app.post("/api/hue/fx")
    async def hue_fx(req: Request):
        body = await req.json()
        if body.get("action") == "stop":
            hue_mgr.player.stop()
            return {"playing": None}
        if not hue_mgr.client.configured:
            return JSONResponse({"error": "hue not configured"}, status_code=409)
        ok = hue_mgr.player.play(int(body.get("index", 0)))
        return {"playing": hue_mgr.player.current if ok else None}

    @app.post("/api/hue/sync")
    async def hue_sync(req: Request):
        body = await req.json()
        if body.get("mode") in ("conditions", "circadian"):
            cfg.set("hue", "sync_mode", value=body["mode"])
        if "enabled" in body:
            cfg.set("hue", "sync_conditions", value=bool(body["enabled"]))
        if not hue_mgr.client.configured:
            return {"configured": False, "sync_conditions":
                    bool(cfg.get("hue", "sync_conditions", default=False)),
                    "sync_mode": cfg.get("hue", "sync_mode", default="conditions")}
        result = hue_mgr.sync_now(service)
        return {"configured": True, **result}

    @app.post("/api/hue/circadian")
    async def hue_circadian(req: Request):
        body = await req.json() if req.headers.get("content-length") else {}
        if body.get("set_mode"):
            cfg.set("hue", "sync_mode", value="circadian")
        state = hue_mgr.circadian_now(service)
        if state is None:
            return JSONResponse({"error": "sun times unavailable"},
                                status_code=503)
        return {"configured": hue_mgr.client.configured, **state}

    return app
