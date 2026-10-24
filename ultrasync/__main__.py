"""UltraSync entry point.

    python -m ultrasync              # web GUI server (flagship, default)
    python -m ultrasync --tui        # terminal UI
    python -m ultrasync --once       # render one full frame to stdout, exit 0
    python -m ultrasync --export-html snapshot.html
    python -m ultrasync --fx-list    # list the 100 Hue effects
"""
import argparse
import sys
from pathlib import Path

from . import __version__
from .config import Config


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="ultrasync",
        description="UltraSync — news, weather, solar & space, unified.")
    parser.add_argument("--version", action="version", version=f"UltraSync {__version__}")
    parser.add_argument("--tui", action="store_true", help="terminal UI instead of the web GUI")
    parser.add_argument("--once", action="store_true",
                        help="render one full frame (all four panels) to stdout and exit")
    parser.add_argument("--export-html", metavar="PATH",
                        help="write a static HTML snapshot and exit")
    parser.add_argument("--theme", "-t", help="theme name (overrides config for this run)")
    parser.add_argument("--host", help="GUI bind host (default from config)")
    parser.add_argument("--port", type=int, help="GUI port (default from config)")
    parser.add_argument("--fx-list", action="store_true", help="list Hue effects and exit")
    args = parser.parse_args(argv)

    cfg = Config()
    if args.theme:
        from . import themes
        if args.theme not in themes.THEMES:
            print(f"unknown theme: {args.theme} (have: {', '.join(themes.theme_names())})",
                  file=sys.stderr)
            return 2
        cfg.data["preferences"]["theme"] = args.theme  # session-only, not saved

    if args.fx_list:
        from .hue_fx import FX
        for i, fx in enumerate(FX):
            print(f"{i + 1:>3}. {fx['name']:<20} {fx['description']}  ({len(fx['steps'])} steps)")
        return 0

    from .service import DataService
    service = DataService(cfg)

    if args.once:
        from .tui import Tui
        app = Tui(cfg, service)
        # one full frame: all four panels, no clear-screen codes
        print(app.render(all_panels=True))
        return 0

    if args.export_html:
        from .export_html import render_snapshot
        out = Path(args.export_html)
        out.write_text(render_snapshot(service, cfg.get("preferences", "theme", default="cyberfire")))
        print(f"wrote {out}")
        return 0

    if args.tui:
        from .tui import Tui
        Tui(cfg, service).run()
        return 0

    # Default: the web GUI.
    host = args.host or cfg.get("server", "host", default="127.0.0.1")
    port = args.port or cfg.get("server", "port", default=8077)
    try:
        import uvicorn
        from .api import create_app
    except ImportError:
        print("FastAPI/uvicorn not installed — run ./run.sh (it bootstraps a venv), "
              "or use --tui.", file=sys.stderr)
        return 3
    print(f"UltraSync {__version__} GUI → http://{host}:{port}  (Ctrl+C to stop)")
    uvicorn.run(create_app(service, cfg), host=host, port=port, log_level="info")
    return 0


if __name__ == "__main__":
    sys.exit(main())
