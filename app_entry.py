#!/usr/bin/env python3
"""Standalone-script entry point (used by the PyInstaller spec and by
installers that need a real file rather than `python -m`)."""
import sys

from ultrasync.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
