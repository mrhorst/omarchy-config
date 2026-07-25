#!/usr/bin/env python3
"""Interactive ChatGPT/Grok subscription usage selector for Waybar."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import html
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

CODEXBAR = str(Path.home() / ".local" / "bin" / "codexbar")
STATE_DIR = Path.home() / ".config" / "waybar" / "state"
STATE_FILE = STATE_DIR / "ai-provider"
CACHE_DIR = Path.home() / ".cache" / "waybar"
CACHE_FILE = CACHE_DIR / "ai-subscriptions.json"
LOCK_FILE = CACHE_DIR / "ai-subscriptions-selector.lock"

PROVIDERS = {
    "codex": {"name": "ChatGPT", "bar": "GPT"},
    "grok": {"name": "Grok", "bar": "Grok"},
}


def command(args: list[str], timeout: int = 45) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)


def selected_provider() -> str:
    try:
        provider = STATE_FILE.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        provider = "codex"
    return provider if provider in PROVIDERS else "codex"


def save_provider(provider: str) -> None:
    if provider not in PROVIDERS:
        raise ValueError(f"Unsupported provider: {provider}")
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    temp = STATE_FILE.with_suffix(".tmp")
    temp.write_text(provider + "\n", encoding="utf-8")
    os.replace(temp, STATE_FILE)
    subprocess.run(["pkill", "-RTMIN+12", "waybar"], check=False)


def save_cache(summaries: dict[str, dict[str, Any]]) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    temp = CACHE_FILE.with_suffix(".tmp")
    payload = {"updated_at": time.time(), "providers": summaries}
    temp.write_text(json.dumps(payload), encoding="utf-8")
    os.chmod(temp, 0o600)
    os.replace(temp, CACHE_FILE)


def load_cache(max_age: int = 600) -> dict[str, dict[str, Any]] | None:
    try:
        payload = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        if time.time() - float(payload.get("updated_at", 0)) > max_age:
            return None
        providers = payload.get("providers") or {}
        if all(provider in providers for provider in PROVIDERS):
            return providers
    except (FileNotFoundError, json.JSONDecodeError, TypeError, ValueError):
        pass
    return None


def fetch_provider(provider: str) -> dict[str, Any]:
    result = command([CODEXBAR, "usage", "--provider", provider, "--source", "auto", "--json"])
    try:
        payload = json.loads(result.stdout) if result.stdout.strip() else []
    except json.JSONDecodeError as exc:
        raise RuntimeError(result.stderr.strip() or f"Invalid {provider} response") from exc
    if not payload:
        raise RuntimeError(result.stderr.strip() or f"No {provider} usage data")
    record = payload[0]
    error = record.get("error")
    if error:
        raise RuntimeError(error.get("message") or f"{provider} usage unavailable")
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"{provider} query failed")
    return record


def parse_timestamp(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.astimezone()
    except ValueError:
        return None


def exact_time(value: str | None, fallback: str | None = None) -> str:
    parsed = parse_timestamp(value)
    if parsed:
        return parsed.strftime("%b %-d, %-I:%M %p")
    return fallback or "unknown"


def remaining_time(value: str | None) -> str:
    parsed = parse_timestamp(value)
    if not parsed:
        return "unknown"
    seconds = max(0, int((parsed - dt.datetime.now().astimezone()).total_seconds()))
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes = seconds // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def window_name(minutes: Any) -> str:
    try:
        minutes = int(minutes)
    except (TypeError, ValueError):
        return "Usage"
    if 9000 <= minutes <= 11000:
        return "Weekly"
    if 40000 <= minutes <= 50000:
        return "Monthly"
    if 1200 <= minutes <= 1800:
        return "Daily"
    if 240 <= minutes <= 360:
        return "5-hour"
    return "Usage"


def summarize(provider: str, record: dict[str, Any]) -> dict[str, Any]:
    usage = record.get("usage") or {}
    if provider == "codex":
        window = usage.get("secondary") or usage.get("primary") or usage.get("tertiary") or {}
    else:
        window = usage.get("primary") or usage.get("secondary") or usage.get("tertiary") or {}
    if window.get("usedPercent") is None:
        raise RuntimeError(f"{PROVIDERS[provider]['name']} returned no subscription usage window")

    used = max(0, min(100, int(round(float(window["usedPercent"])))))
    remaining = 100 - used
    resets_at = window.get("resetsAt")
    reset_exact = exact_time(resets_at, window.get("resetDescription"))
    reset_in = remaining_time(resets_at)
    label = window_name(window.get("windowMinutes"))

    reset_credits = usage.get("codexResetCredits") or {}
    credit_rows = [
        credit
        for credit in (reset_credits.get("credits") or [])
        if credit.get("status") == "available"
    ]
    credit_rows.sort(key=lambda credit: credit.get("expires_at") or "")
    credit_count = int(reset_credits.get("availableCount", len(credit_rows)) or 0)
    credit_expirations = [exact_time(credit.get("expires_at")) for credit in credit_rows]

    css_class = "critical" if remaining <= 15 else "warning" if remaining <= 35 else "healthy"
    return {
        "provider": provider,
        "name": PROVIDERS[provider]["name"],
        "bar_name": PROVIDERS[provider]["bar"],
        "used": used,
        "remaining": remaining,
        "window_label": label,
        "reset_exact": reset_exact,
        "reset_in": reset_in,
        "reset_credits": credit_count,
        "credit_expirations": credit_expirations,
        "account": usage.get("accountEmail") or "",
        "class": css_class,
    }


def get_summary(provider: str) -> dict[str, Any]:
    return summarize(provider, fetch_provider(provider))


def unavailable(provider: str, exc: Exception) -> dict[str, Any]:
    return {
        "provider": provider,
        "name": PROVIDERS[provider]["name"],
        "bar_name": PROVIDERS[provider]["bar"],
        "error": str(exc),
        "class": "unavailable",
    }


def all_summaries() -> dict[str, dict[str, Any]]:
    results: dict[str, dict[str, Any]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(get_summary, provider): provider for provider in PROVIDERS}
        for future in concurrent.futures.as_completed(futures):
            provider = futures[future]
            try:
                results[provider] = future.result()
            except Exception as exc:
                results[provider] = unavailable(provider, exc)
    return results


def tooltip(summary: dict[str, Any]) -> str:
    if summary.get("error"):
        return (
            f"{summary['name']} usage unavailable\n"
            f"{summary['error']}\n"
            "Click to choose a subscription"
        )

    lines = [
        f"{summary['name']} — {summary['window_label']}",
        f"Remaining: {summary['remaining']}%",
        f"Used: {summary['used']}%",
        f"Resets: {summary['reset_exact']} ({summary['reset_in']} remaining)",
    ]
    if summary["provider"] == "codex":
        lines.append(f"Full reset credits: {summary['reset_credits']}")
        for index, expiration in enumerate(summary["credit_expirations"], start=1):
            lines.append(f"  Reset {index} expires: {expiration}")
    if summary.get("account"):
        lines.append(summary["account"])
    lines.append("Click to switch subscription")
    return "\n".join(lines)


def notification_details(summary: dict[str, Any]) -> tuple[str, str, str]:
    if summary.get("error"):
        lines = [
            "STATUS",
            "Usage unavailable",
            "",
            "REASON",
            summary["error"],
        ]
        if summary["provider"] == "grok":
            lines.extend(["", "AUTHENTICATE", "grok login --oauth"])
        return f"{summary['name']} usage unavailable", "\n".join(lines), "normal"

    title = f"{summary['name']} · {summary['remaining']}% remaining"
    lines = [
        f"{summary['window_label'].upper()} ALLOWANCE",
        f"Remaining: {summary['remaining']}%   •   Used: {summary['used']}%",
        "",
        "QUOTA RESET",
        f"{summary['reset_exact']}   •   {summary['reset_in']} remaining",
    ]

    if summary["provider"] == "codex":
        lines.extend(["", "FULL-RESET CREDITS", f"{summary['reset_credits']} available"])
        for index, expiration in enumerate(summary["credit_expirations"], start=1):
            lines.append(f"{index}. Expires {expiration}")

    if summary.get("account"):
        lines.extend(["", "ACCOUNT", summary["account"]])

    return title, "\n".join(lines), "low"


def current_summaries(max_age: int = 240, force: bool = False) -> dict[str, dict[str, Any]]:
    summaries = None if force else load_cache(max_age=max_age)
    if summaries is None:
        summaries = all_summaries()
        save_cache(summaries)
    return summaries


def bar_payload(force: bool = False) -> dict[str, Any]:
    provider = selected_provider()
    summary = current_summaries(force=force)[provider]
    if summary.get("error"):
        text = f"{PROVIDERS[provider]['bar']} !"
    else:
        text = f"{summary['bar_name']} {summary['remaining']}%"
        if summary["provider"] == "codex" and summary["reset_credits"]:
            text += f" · R{summary['reset_credits']}"
    return {
        "text": text,
        "tooltip": html.escape(tooltip(summary)),
        "class": [summary["class"], f"provider-{provider}"],
        "alt": provider,
    }


def menu_line(summary: dict[str, Any], selected: str) -> str:
    marker = "●" if summary["provider"] == selected else "○"
    if summary.get("error"):
        reason = summary["error"].replace("\n", " ")
        if len(reason) > 72:
            reason = reason[:69] + "…"
        return f"{marker} {summary['name']:<8}  unavailable  · {reason}"

    line = (
        f"{marker} {summary['name']:<8}  {summary['remaining']:>3}% left"
        f"  · resets {summary['reset_exact']} ({summary['reset_in']})"
    )
    if summary["provider"] == "codex":
        next_expiry = summary["credit_expirations"][0] if summary["credit_expirations"] else "none"
        line += f"  · {summary['reset_credits']} reset credits; next expires {next_expiry}"
    return line


def menu_rows() -> tuple[list[str], dict[str, str], dict[str, dict[str, Any]]]:
    selected = selected_provider()
    summaries = current_summaries(max_age=600)
    rows: list[str] = []
    mapping: dict[str, str] = {}
    for provider in PROVIDERS:
        row = menu_line(summaries[provider], selected)
        rows.append(row)
        mapping[row] = provider
    return rows, mapping, summaries


def popup_address() -> str | None:
    try:
        clients = json.loads(command(["hyprctl", "clients", "-j"], timeout=5).stdout)
        client = next(item for item in clients if item.get("title") == "AI subscription selector")
        return str(client["address"])
    except Exception:
        return None


def close_popup() -> bool:
    address = popup_address()
    if not address:
        return False
    command(["hyprctl", "dispatch", "closewindow", f"address:{address}"], timeout=5)
    return True


def choose_provider() -> int:
    # A second Waybar click toggles the existing selector closed.
    if close_popup():
        return 0

    import fcntl

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    lock_handle = LOCK_FILE.open("w", encoding="utf-8")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        # Covers a very fast second click before Hyprland has registered the
        # first surface. Wait briefly for it, close it, and never open another.
        for _ in range(10):
            if close_popup():
                break
            time.sleep(0.05)
        lock_handle.close()
        return 0

    _, _, summaries = menu_rows()

    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Gdk", "4.0")
    from gi.repository import Gdk, GLib, Gtk

    Gtk.init()
    loop = GLib.MainLoop()
    popup_width = 500
    popup_height = 225
    window = Gtk.Window(title="AI subscription selector")
    window.set_decorated(False)
    window.set_default_size(popup_width, popup_height)
    window.set_resizable(False)

    layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    layout.set_margin_top(16)
    layout.set_margin_bottom(16)
    layout.set_margin_start(16)
    layout.set_margin_end(16)

    heading = Gtk.Label()
    heading.set_markup("<b>Display AI subscription</b>")
    heading.set_xalign(0)
    heading.add_css_class("title-3")
    layout.append(heading)

    current = selected_provider()
    for provider in PROVIDERS:
        summary = summaries[provider]
        button = Gtk.Button()
        button.set_hexpand(True)
        button.add_css_class("subscription-row")
        if provider == current:
            button.add_css_class("selected")
        if summary.get("error"):
            button.add_css_class("unavailable")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        marker = "●" if provider == current else "○"
        if summary.get("error"):
            title_text = f"{marker}  {summary['name']}   unavailable"
            detail_text = summary["error"].replace("\n", " ")
        else:
            title_text = f"{marker}  {summary['name']}   {summary['remaining']}% left"
            detail_text = f"Resets {summary['reset_exact']} ({summary['reset_in']})"
            if provider == "codex":
                next_expiry = summary["credit_expirations"][0] if summary["credit_expirations"] else "none"
                detail_text += f"\n{summary['reset_credits']} reset credits · next expires {next_expiry}"

        title_label = Gtk.Label()
        title_label.set_markup(f"<b>{html.escape(title_text)}</b>")
        title_label.set_xalign(0)
        detail_label = Gtk.Label(label=detail_text)
        detail_label.set_xalign(0)
        detail_label.set_wrap(True)
        detail_label.add_css_class("subscription-detail")
        card.append(title_label)
        card.append(detail_label)
        button.set_child(card)

        def selected(_button: Gtk.Button, chosen: str = provider) -> None:
            save_provider(chosen)
            window.close()

        button.connect("clicked", selected)
        layout.append(button)

    controller = Gtk.EventControllerKey()

    def key_pressed(_controller: Gtk.EventControllerKey, keyval: int, _keycode: int, _state: Gdk.ModifierType) -> bool:
        if keyval == Gdk.KEY_Escape:
            window.close()
            return True
        return False

    def quit_main_loop() -> bool:
        loop.quit()
        return False

    def close_requested(_window: Gtk.Window) -> bool:
        # Let GTK finish removing the surface before terminating its loop.
        GLib.timeout_add(75, quit_main_loop)
        return False

    controller.connect("key-pressed", key_pressed)
    window.add_controller(controller)
    window.connect("close-request", close_requested)

    css = Gtk.CssProvider()
    css.load_from_string(
        "window { background: #121212; color: #bebebe; border: 1px solid #3a3a3a; border-radius: 9px; }"
        ".subscription-row { padding: 12px; border-radius: 7px; }"
        ".subscription-row.selected { border: 1px solid #e68e0d; }"
        ".subscription-row.unavailable { color: #8a8a8d; }"
    )
    display = Gdk.Display.get_default()
    if display is not None:
        Gtk.StyleContext.add_provider_for_display(
            display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    window.set_child(layout)
    window.present()
    loop.run()
    return 0


def notify_selected() -> int:
    if close_popup():
        time.sleep(0.1)
    provider = selected_provider()
    summary = current_summaries(max_age=600)[provider]
    title, body, urgency = notification_details(summary)
    subprocess.run(
        ["notify-send", "-a", "AIUsage", "-u", urgency, "-t", "5000", title, body],
        check=False,
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--select", action="store_true", help="Open the provider chooser")
    parser.add_argument("--list", action="store_true", help="Print chooser rows without opening Walker")
    parser.add_argument("--set", choices=PROVIDERS, help="Persist a provider directly")
    parser.add_argument("--notify", action="store_true", help="Show selected-provider details")
    parser.add_argument("--refresh", action="store_true", help="Force-refresh both provider snapshots")
    args = parser.parse_args()

    if args.set:
        save_provider(args.set)
        return 0
    if args.list:
        rows, _, _ = menu_rows()
        print("\n".join(rows))
        return 0
    if args.select:
        return choose_provider()
    if args.notify:
        return notify_selected()
    if args.refresh:
        print(json.dumps(bar_payload(force=True)))
        return 0

    print(json.dumps(bar_payload()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
