import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def test_once_headless_frame(tmp_path):
    env = dict(os.environ)
    env["ULTRASYNC_NO_NET"] = "1"
    env["ULTRASYNC_CONFIG_DIR"] = str(tmp_path / "cfg")
    env["ULTRASYNC_CACHE_DIR"] = str(tmp_path / "cache")
    proc = subprocess.run(
        [sys.executable, "-m", "ultrasync", "--once"],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=60)
    assert proc.returncode == 0, proc.stderr
    out = proc.stdout
    for marker in ("ULTRASYNC", "NEWS", "WEATHER", "SOLAR", "SPACE"):
        assert marker in out


def test_export_html(tmp_path):
    env = dict(os.environ)
    env["ULTRASYNC_NO_NET"] = "1"
    env["ULTRASYNC_CONFIG_DIR"] = str(tmp_path / "cfg")
    env["ULTRASYNC_CACHE_DIR"] = str(tmp_path / "cache")
    target = tmp_path / "snapshot.html"
    proc = subprocess.run(
        [sys.executable, "-m", "ultrasync", "--export-html", str(target)],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=60)
    assert proc.returncode == 0, proc.stderr
    html = target.read_text()
    assert "ULTRASYNC" in html and "NEWS" in html and "SOLAR" in html
