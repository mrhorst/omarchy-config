#!/usr/bin/env python3
"""Keep Omarchy awake while Stremio is fullscreen.

Omarchy Shell's IdleMonitor currently ignores Hyprland's per-window idle
inhibitor state. This guard uses Omarchy's own idle IPC and only re-enables
idle when it was the component that disabled it.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

INTERVAL_SECONDS = 2
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "stremio-idle-guard"
OWNER_MARKER = STATE_DIR / "owns-stay-awake"
STOP = False


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=False, capture_output=True, text=True, timeout=5)


def stremio_is_fullscreen() -> bool:
    result = run("hyprctl", "clients", "-j")
    if result.returncode != 0:
        return False
    try:
        clients = json.loads(result.stdout)
    except json.JSONDecodeError:
        return False
    return any(
        client.get("class") == "com.stremio.Stremio"
        and bool(client.get("visible"))
        and int(client.get("fullscreen", 0)) != 0
        for client in clients
    )


def idle_enabled() -> bool | None:
    result = run("omarchy-shell", "idle", "status")
    if result.returncode != 0:
        return None
    try:
        return bool(json.loads(result.stdout)["enabled"])
    except (json.JSONDecodeError, KeyError, TypeError):
        return None


def set_idle(enabled: bool) -> bool:
    method = "enable" if enabled else "disable"
    return run("omarchy-shell", "idle", method).returncode == 0


def action_for(active: bool, enabled: bool, owned: bool) -> str:
    if active and enabled:
        return "disable-and-own"
    if not active and owned:
        return "release" if enabled else "enable-and-release"
    return "none"


def reconcile(active: bool) -> None:
    enabled = idle_enabled()
    if enabled is None:
        return

    action = action_for(active, enabled, OWNER_MARKER.exists())
    if action == "disable-and-own":
        if set_idle(False):
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            OWNER_MARKER.touch()
    elif action == "enable-and-release":
        if set_idle(True):
            OWNER_MARKER.unlink(missing_ok=True)
    elif action == "release":
        OWNER_MARKER.unlink(missing_ok=True)


def stop(_signum: int, _frame: object) -> None:
    global STOP
    STOP = True


def self_test() -> int:
    cases = {
        (True, True, False): "disable-and-own",
        (True, False, False): "none",
        (True, False, True): "none",
        (False, False, True): "enable-and-release",
        (False, True, True): "release",
        (False, True, False): "none",
    }
    for inputs, expected in cases.items():
        actual = action_for(*inputs)
        assert actual == expected, (inputs, actual, expected)
    print("stremio-idle-guard self-test: PASS")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        while not STOP:
            reconcile(stremio_is_fullscreen())
            time.sleep(INTERVAL_SECONDS)
    finally:
        # A stopped/removed guard must not strand Omarchy in stay-awake mode.
        if OWNER_MARKER.exists():
            if idle_enabled() is False:
                set_idle(True)
            OWNER_MARKER.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
