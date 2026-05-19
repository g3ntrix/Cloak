#!/usr/bin/env python3
"""
PyInstaller entry point for Cloak.app.

Freezes the SNI-spoofing listener (main.py + fake_tcp + scapy) into a
self-contained binary so end users never need system Python or CLT.
"""

from __future__ import annotations

import os
import sys


def _resource_dir() -> str:
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        return meipass
    return os.path.dirname(os.path.abspath(__file__))


def _repo_root() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def main() -> None:
    res = _resource_dir()
    repo = _repo_root()
    for p in (repo, res):
        if p not in sys.path:
            sys.path.insert(0, p)

    from main import run as run_listener

    run_listener()


if __name__ == "__main__":
    main()
