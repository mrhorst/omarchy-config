#!/usr/bin/env python3
"""Emit compact JSON for the Omarchy system-health bar widget."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import time
from pathlib import Path


def cpu_percent() -> float:
    def sample() -> tuple[int, int]:
        fields = [int(value) for value in Path("/proc/stat").read_text().splitlines()[0].split()[1:]]
        idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
        return sum(fields), idle

    total_a, idle_a = sample()
    time.sleep(0.15)
    total_b, idle_b = sample()
    delta = total_b - total_a
    return 0.0 if delta <= 0 else 100.0 * (1.0 - (idle_b - idle_a) / delta)


def memory_percent() -> float:
    values: dict[str, int] = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.split()[0])
    total = values["MemTotal"]
    return 100.0 * (total - values["MemAvailable"]) / total


def disk_percent() -> float:
    stats = shutil.disk_usage(Path.home())
    return 100.0 * stats.used / stats.total


def nvidia_stats() -> tuple[float | None, float | None]:
    if not shutil.which("nvidia-smi"):
        return None, None
    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=utilization.gpu,temperature.gpu",
            "--format=csv,noheader,nounits",
        ],
        capture_output=True,
        text=True,
        timeout=2,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None, None
    first = result.stdout.splitlines()[0]
    utilization, temperature = (float(value.strip()) for value in first.split(",", 1))
    return utilization, temperature


def state_for(cpu: float, memory: float, disk: float, gpu: float | None, temperature: float | None) -> str:
    values = [cpu, memory, disk]
    if gpu is not None:
        values.append(gpu)
    if max(values) >= 95 or (temperature is not None and temperature >= 85):
        return "critical"
    if max(values) >= 85 or (temperature is not None and temperature >= 75):
        return "warning"
    return "healthy"


def collect() -> dict[str, str]:
    cpu = cpu_percent()
    memory = memory_percent()
    disk = disk_percent()
    gpu, temperature = nvidia_stats()
    state = state_for(cpu, memory, disk, gpu, temperature)

    text = f"󰍛 {cpu:.0f}%"
    if gpu is not None:
        text += f" 󰢮 {gpu:.0f}%"
    if temperature is not None:
        text += f" {temperature:.0f}°"

    details = [
        f"CPU: {cpu:.1f}%",
        f"Memory: {memory:.1f}%",
        f"Home disk: {disk:.1f}%",
    ]
    if gpu is not None:
        details.append(f"NVIDIA GPU: {gpu:.1f}%")
    if temperature is not None:
        details.append(f"GPU temperature: {temperature:.0f}°C")
    details.append(f"State: {state}")

    return {"text": text, "tooltip": "\n".join(details), "state": state}


def main() -> int:
    try:
        value = collect()
    except Exception as error:  # The widget should fail visible, not disappear.
        value = {"text": "󰍛 ?", "tooltip": f"System health unavailable: {error}", "state": "unknown"}

    if "--notify" in sys.argv:
        if command := shutil.which("notify-send"):
            urgency = "critical" if value["state"] == "critical" else "normal"
            subprocess.run(
                [command, "-a", "OmarchySystemHealth", "-u", urgency, "System health", value["tooltip"]],
                check=False,
            )
    else:
        print(json.dumps(value, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
