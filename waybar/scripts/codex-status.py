#!/usr/bin/env python3
"""Waybar module for Codex quota using the official CodexBar CLI."""

import html
import json
from pathlib import Path
import subprocess
import sys

CODEXBAR = str(Path.home() / ".local" / "bin" / "codexbar")


def run(args: list[str], timeout: int = 35) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)


def usage_json() -> dict:
    result = run([CODEXBAR, "usage", "--provider", "codex", "--source", "cli", "--json"])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "CodexBar query failed")
    payload = json.loads(result.stdout)
    if not payload:
        raise RuntimeError("CodexBar returned no usage data")
    return payload[0]


def summarize(data: dict) -> tuple[str, str, str]:
    usage = data.get("usage") or {}
    window = usage.get("secondary") or usage.get("primary") or {}
    used = int(round(float(window.get("usedPercent", 0))))
    remaining = max(0, min(100, 100 - used))
    reset = window.get("resetDescription") or "Unknown"
    pace = ((data.get("pace") or {}).get("secondary") or {}).get("summary")
    account = usage.get("accountEmail") or "Codex account"

    lines = [
        f"Codex weekly: {remaining}% left",
        f"Used: {used}%",
        f"Resets: {reset}",
    ]
    if pace:
        lines.append(str(pace))
    lines.append(str(account))

    css_class = "critical" if remaining <= 15 else "warning" if remaining <= 35 else "healthy"
    return f"Cdx {remaining}%", "\n".join(lines), css_class


def notify() -> int:
    result = run([CODEXBAR, "usage", "--provider", "codex", "--source", "cli", "--no-color"])
    body = result.stdout.strip() if result.returncode == 0 else (result.stderr.strip() or "Unable to read Codex usage")
    subprocess.run(["notify-send", "-u", "low", "-t", "15000", "Codex usage", body], check=False)
    return result.returncode


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--notify":
        return notify()

    try:
        text, tooltip, css_class = summarize(usage_json())
        print(json.dumps({"text": text, "tooltip": html.escape(tooltip), "class": css_class}))
        return 0
    except Exception as exc:  # Waybar should degrade instead of disappearing.
        print(json.dumps({"text": "Cdx ?", "tooltip": html.escape(str(exc)), "class": "unavailable"}))
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
