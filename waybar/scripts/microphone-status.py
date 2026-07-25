#!/usr/bin/env python3
"""Default microphone volume/mute status for Waybar."""

import html
import json
import re
import subprocess
import sys
import time

SOURCE = "@DEFAULT_AUDIO_SOURCE@"


def toggle() -> None:
    subprocess.run(["wpctl", "set-mute", SOURCE, "toggle"], check=False)
    time.sleep(0.1)


def status() -> tuple[str, str, str]:
    result = subprocess.run(["wpctl", "get-volume", SOURCE], text=True, capture_output=True, timeout=5, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Microphone unavailable")
    match = re.search(r"Volume:\s*([0-9.]+)", result.stdout)
    volume = round(float(match.group(1)) * 100) if match else 0
    muted = "MUTED" in result.stdout.upper()
    text = "" if muted else ""
    tooltip = f"Microphone: {'muted' if muted else 'live'}\nInput volume: {volume}%\nClick to toggle mute"
    return text, tooltip, "muted" if muted else "active"


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--toggle":
        toggle()
        return 0
    try:
        text, tooltip, css_class = status()
        print(json.dumps({"text": text, "tooltip": html.escape(tooltip), "class": css_class}))
    except Exception as exc:
        print(json.dumps({"text": "", "tooltip": html.escape(str(exc)), "class": "unavailable"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
