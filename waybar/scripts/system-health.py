#!/usr/bin/env python3
"""Compact CPU, memory, GPU and disk health for Waybar."""

import html
import json
import os
import subprocess
import sys
import time


def cpu_sample() -> tuple[int, int]:
    fields = [int(value) for value in open("/proc/stat", encoding="utf-8").readline().split()[1:]]
    idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
    return idle, sum(fields)


def cpu_percent() -> int:
    idle1, total1 = cpu_sample()
    time.sleep(0.15)
    idle2, total2 = cpu_sample()
    delta = max(1, total2 - total1)
    return max(0, min(100, round(100 * (1 - (idle2 - idle1) / delta))))


def memory_percent() -> int:
    values: dict[str, int] = {}
    with open("/proc/meminfo", encoding="utf-8") as handle:
        for line in handle:
            key, value = line.split(":", 1)
            values[key] = int(value.strip().split()[0])
    total = values["MemTotal"]
    available = values.get("MemAvailable", values.get("MemFree", 0))
    return round(100 * (total - available) / total)


def disk_percent() -> int:
    stats = os.statvfs("/home")
    total = stats.f_blocks
    available = stats.f_bavail
    return round(100 * (total - available) / total) if total else 0


def gpu_stats() -> tuple[int | None, int | None, int | None]:
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"],
        text=True,
        capture_output=True,
        timeout=5,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None, None, None
    temp, utilization, used, total = [int(float(item.strip())) for item in result.stdout.splitlines()[0].split(",")]
    memory = round(100 * used / total) if total else 0
    return temp, utilization, memory


def collect() -> tuple[dict, str, str, str]:
    cpu = cpu_percent()
    memory = memory_percent()
    disk = disk_percent()
    gpu_temp, gpu_usage, gpu_memory = gpu_stats()
    load1 = os.getloadavg()[0]

    if gpu_temp is None:
        text = f"󰍛 {cpu}%   {memory}%"
    else:
        text = f"󰍛 {cpu}%  󰢮 {gpu_temp}°"

    lines = [
        f"CPU: {cpu}% (load {load1:.2f})",
        f"Memory: {memory}%",
        f"Disk /home: {disk}%",
    ]
    if gpu_temp is not None:
        lines.extend([f"GPU: {gpu_usage}%", f"GPU memory: {gpu_memory}%", f"GPU temperature: {gpu_temp}°C"])

    critical = cpu >= 95 or memory >= 95 or disk >= 95 or (gpu_temp is not None and gpu_temp >= 85)
    warning = cpu >= 80 or memory >= 85 or disk >= 90 or (gpu_temp is not None and gpu_temp >= 75)
    css_class = "critical" if critical else "warning" if warning else "healthy"
    values = {"cpu": cpu, "memory": memory, "disk": disk, "gpu_temp": gpu_temp, "gpu_usage": gpu_usage, "gpu_memory": gpu_memory}
    return values, text, "\n".join(lines), css_class


def main() -> int:
    try:
        values, text, tooltip, css_class = collect()
        if len(sys.argv) > 1 and sys.argv[1] == "--notify":
            subprocess.run(["notify-send", "-u", "low", "-t", "12000", "System health", tooltip], check=False)
        else:
            print(json.dumps({"text": text, "tooltip": html.escape(tooltip), "class": css_class, "percentage": values["cpu"]}))
    except Exception as exc:
        if not (len(sys.argv) > 1 and sys.argv[1] == "--notify"):
            print(json.dumps({"text": "SYS ?", "tooltip": html.escape(str(exc)), "class": "unavailable"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
