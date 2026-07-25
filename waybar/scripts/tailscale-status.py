#!/usr/bin/env python3
"""Tailscale state, active peers, and health warnings for Waybar."""

import html
import json
import subprocess
import sys


def collect() -> tuple[str, str, str]:
    result = subprocess.run(["tailscale", "status", "--json"], text=True, capture_output=True, timeout=8, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "tailscale status failed")
    data = json.loads(result.stdout)
    state = data.get("BackendState", "Unknown")
    online = state == "Running" and bool((data.get("Self") or {}).get("Online", False))
    ip = ((data.get("TailscaleIPs") or ["No IP"])[0])
    peers = sorted(
        peer.get("HostName", "unknown")
        for peer in (data.get("Peer") or {}).values()
        if peer.get("Online")
    )
    health = data.get("Health") or []

    lines = [f"Tailscale: {state}", f"This machine: {ip}", f"Online peers: {', '.join(peers) if peers else 'none'}"]
    if health:
        lines.append("Warnings:")
        lines.extend(f"• {warning}" for warning in health)

    css_class = "offline" if not online else "warning" if health else "healthy"
    text = "󰖂" if online else "󰖪"
    return text, "\n".join(lines), css_class


def main() -> int:
    try:
        text, tooltip, css_class = collect()
        if len(sys.argv) > 1 and sys.argv[1] == "--notify":
            urgency = "normal" if css_class == "warning" else "low"
            subprocess.run(["notify-send", "-u", urgency, "-t", "15000", "Tailscale", tooltip], check=False)
        else:
            print(json.dumps({"text": text, "tooltip": html.escape(tooltip), "class": css_class}))
    except Exception as exc:
        if len(sys.argv) > 1 and sys.argv[1] == "--notify":
            subprocess.run(["notify-send", "-u", "normal", "Tailscale unavailable", str(exc)], check=False)
        else:
            print(json.dumps({"text": "󰖪", "tooltip": html.escape(str(exc)), "class": "offline"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
