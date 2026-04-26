"""Capture CH1 and CH2 from the same USB block to diagnose CH2 timing."""

from __future__ import annotations

import argparse
import csv
import math
from datetime import datetime
from pathlib import Path
from statistics import median

from hantek_usb_backend import Hantek6022USBBackend


def edge_metrics(time_s: list[float], voltage_v: list[float]) -> dict[str, float | int]:
    finite = [value for value in voltage_v if math.isfinite(value)]
    if len(finite) < 3:
        return {"edge_count": 0}

    sorted_values = sorted(finite)
    n_values = len(sorted_values)
    p5 = sorted_values[max(0, round(0.05 * n_values) - 1)]
    p95 = sorted_values[min(n_values - 1, round(0.95 * n_values) - 1)]
    amplitude = p95 - p5
    if not math.isfinite(amplitude) or amplitude <= 0:
        return {"edge_count": 0}

    level = (p5 + p95) / 2.0
    hysteresis = max(0.02, 0.08 * amplitude)
    low = level - hysteresis

    armed = False
    edges: list[int] = []
    for index, value in enumerate(voltage_v):
        if not math.isfinite(value):
            armed = False
            continue
        if value <= low:
            armed = True
        elif armed and value >= level:
            edges.append(index)
            armed = False

    periods_ms = [
        (time_s[right] - time_s[left]) * 1e3
        for left, right in zip(edges, edges[1:])
        if time_s[right] > time_s[left]
    ]
    metrics: dict[str, float | int] = {
        "edge_count": len(edges),
        "level_v": level,
        "hysteresis_v": hysteresis,
        "vpp_v": max(finite) - min(finite),
        "mean_v": sum(finite) / len(finite),
    }
    if periods_ms:
        period_median = median(periods_ms)
        period_min = min(periods_ms)
        period_max = max(periods_ms)
        metrics.update(
            {
                "period_median_ms": period_median,
                "period_min_ms": period_min,
                "period_max_ms": period_max,
                "period_spread_pct": 100.0 * (period_max - period_min) / period_median,
                "frequency_hz": 1000.0 / period_median,
            }
        )
    return metrics


def write_dual_csv(capture: dict[str, object], output_path: Path) -> Path:
    output_path = output_path.expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    time_s = capture["time"]
    ch1 = capture["ch1"]
    ch2 = capture["ch2"]
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["t / s", "CH1 / V", "CH2 / V"])
        for values in zip(time_s, ch1, ch2):
            writer.writerow([f"{float(values[0]):.10f}", f"{float(values[1]):.10f}", f"{float(values[2]):.10f}"])
    return output_path


def print_metrics(name: str, metrics: dict[str, float | int]) -> None:
    print(f"{name}:")
    for key in [
        "edge_count",
        "vpp_v",
        "mean_v",
        "level_v",
        "period_median_ms",
        "period_min_ms",
        "period_max_ms",
        "period_spread_pct",
        "frequency_hz",
    ]:
        if key in metrics:
            value = metrics[key]
            if isinstance(value, float):
                print(f"  {key}: {value:.6g}")
            else:
                print(f"  {key}: {value}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Diagnose CH2 by capturing CH1 and CH2 from one dual USB block.")
    parser.add_argument("--sample-rate", type=float, default=10_000_000.0)
    parser.add_argument("--n-samples", type=int, default=100_000)
    parser.add_argument("--volts-per-div", type=float, default=1.0)
    parser.add_argument("--project-root", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", default=None)
    parser.add_argument("--log-path", default=None)
    parser.add_argument("--quiet-log", action="store_true")
    args = parser.parse_args()

    project_root = Path(args.project_root).expanduser().resolve()
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = Path(args.output) if args.output else project_root / "data" / "raw" / f"dual_ch1_ch2_{stamp}.csv"
    log_path = Path(args.log_path) if args.log_path else project_root / "data" / "logs" / f"dual_ch1_ch2_{stamp}.log"

    backend = Hantek6022USBBackend(
        project_root=project_root,
        debug_log_path=log_path,
        debug_echo=not args.quiet_log,
    )
    try:
        capture = backend.acquire_dual(
            sample_rate=args.sample_rate,
            n_samples=args.n_samples,
            volts_per_div=args.volts_per_div,
        )
    finally:
        backend.close()

    csv_path = write_dual_csv(capture, output)
    time_s = [float(value) for value in capture["time"]]
    ch1 = [float(value) for value in capture["ch1"]]
    ch2 = [float(value) for value in capture["ch2"]]

    print(f"csv: {csv_path}")
    print(f"log: {log_path}")
    print(f"sample_rate: {capture['sample_rate']}")
    print(f"n_samples: {capture['n_samples']}")
    print_metrics("CH1", edge_metrics(time_s, ch1))
    print_metrics("CH2", edge_metrics(time_s, ch2))
    print("note: if only the CH2 probe is on the calibrator, CH2 should have the clean square wave.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
