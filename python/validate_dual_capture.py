"""Validate a CH1+CH2 CSV capture for timing and square-wave sanity."""

from __future__ import annotations

import argparse
import csv
import glob
import math
from pathlib import Path
from statistics import median


def normalize_header(header: str) -> str:
    return "".join(ch for ch in header.lower() if ch.isalnum())


def latest_dual_csv(project_root: Path) -> Path:
    patterns = [
        str(project_root / "data" / "processed" / "hantek_dual_*.csv"),
        str(project_root / "data" / "raw" / "dual_diag_*.csv"),
        str(project_root / "data" / "raw" / "dual_ch1_ch2_*.csv"),
    ]
    matches: list[str] = []
    for pattern in patterns:
        matches.extend(glob.glob(pattern))
    if not matches:
        raise FileNotFoundError("No dual CSV capture found in data/processed or data/raw")
    return Path(max(matches, key=lambda item: Path(item).stat().st_mtime))


def read_dual_csv(path: Path) -> tuple[list[float], list[float], list[float]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        rows = [row for row in reader if row]
    if len(rows) < 2:
        raise ValueError(f"CSV is empty: {path}")

    headers = [normalize_header(value) for value in rows[0]]
    time_idx = next((i for i, h in enumerate(headers) if h in {"ts", "time", "times"}), 0)
    ch1_idx = next((i for i, h in enumerate(headers) if "ch1" in h and ("v" in h or h == "ch1")), None)
    ch2_idx = next((i for i, h in enumerate(headers) if "ch2" in h and ("v" in h or h == "ch2")), None)
    if ch1_idx is None or ch2_idx is None:
        if len(headers) >= 3:
            ch1_idx, ch2_idx = 1, 2
        else:
            raise ValueError(f"Could not find CH1/CH2 columns in {path}")

    time_s: list[float] = []
    ch1: list[float] = []
    ch2: list[float] = []
    for row in rows[1:]:
        if len(row) <= max(time_idx, ch1_idx, ch2_idx):
            continue
        try:
            t_value = float(row[time_idx])
            ch1_value = float(row[ch1_idx])
            ch2_value = float(row[ch2_idx])
        except ValueError:
            continue
        if math.isfinite(t_value) and math.isfinite(ch1_value) and math.isfinite(ch2_value):
            time_s.append(t_value)
            ch1.append(ch1_value)
            ch2.append(ch2_value)
    if not time_s:
        raise ValueError(f"No numeric samples found in {path}")
    return time_s, ch1, ch2


def edge_metrics(time_s: list[float], voltage_v: list[float]) -> dict[str, float | int]:
    finite = [value for value in voltage_v if math.isfinite(value)]
    if len(finite) < 3:
        return {"edge_count": 0}

    sorted_values = sorted(finite)
    n_values = len(sorted_values)
    low = median(sorted_values[: max(1, round(0.20 * n_values))])
    high = median(sorted_values[max(0, round(0.80 * n_values)) :])
    level = (low + high) / 2.0
    amplitude = high - low
    if not math.isfinite(amplitude) or amplitude <= 0:
        return {"edge_count": 0}

    armed = False
    low_threshold = level - max(0.02, 0.08 * amplitude)
    edges: list[int] = []
    for index, value in enumerate(voltage_v):
        if not math.isfinite(value):
            armed = False
        elif value <= low_threshold:
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
        "low_v": low,
        "high_v": high,
        "vpp_v": max(finite) - min(finite),
        "mean_v": sum(finite) / len(finite),
        "duty_cycle_pct": 100.0 * sum(1 for value in voltage_v if value >= level) / len(voltage_v),
    }
    if periods_ms:
        period_median = median(periods_ms)
        period_min = min(periods_ms)
        period_max = max(periods_ms)
        metrics.update(
            {
                "period_median_ms": period_median,
                "period_spread_pct": 100.0 * (period_max - period_min) / period_median,
                "frequency_hz": 1000.0 / period_median,
            }
        )
    return metrics


def time_metrics(time_s: list[float]) -> dict[str, float | int]:
    deltas = [right - left for left, right in zip(time_s, time_s[1:])]
    positive = [value for value in deltas if value > 0 and math.isfinite(value)]
    if not positive:
        raise ValueError("Time column is not strictly increasing")
    dt_median = median(positive)
    max_step_error_pct = max(abs(value - dt_median) for value in positive) / dt_median * 100.0
    non_positive = len(deltas) - len(positive)
    return {
        "samples": len(time_s),
        "dt_median_s": dt_median,
        "sample_rate_hz": 1.0 / dt_median,
        "non_positive_steps": non_positive,
        "max_step_error_pct": max_step_error_pct,
    }


def print_metrics(name: str, metrics: dict[str, float | int]) -> None:
    print(f"{name}:")
    for key, value in metrics.items():
        if isinstance(value, float):
            print(f"  {key}: {value:.6g}")
        else:
            print(f"  {key}: {value}")


def validate_channel(name: str, metrics: dict[str, float | int], args: argparse.Namespace) -> list[str]:
    failures: list[str] = []
    edge_count = int(metrics.get("edge_count", 0))
    if edge_count < args.min_edges:
        failures.append(f"{name}: only {edge_count} rising edges")
    frequency = float(metrics.get("frequency_hz", float("nan")))
    if math.isfinite(frequency) and args.expected_frequency > 0:
        error_pct = abs(frequency - args.expected_frequency) / args.expected_frequency * 100.0
        if error_pct > args.frequency_tolerance_pct:
            failures.append(f"{name}: frequency error {error_pct:.3g}%")
    tjit = float(metrics.get("period_spread_pct", float("nan")))
    if math.isfinite(tjit) and tjit > args.max_tjit_pct:
        failures.append(f"{name}: Tjit {tjit:.3g}% > {args.max_tjit_pct:.3g}%")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a dual CH1+CH2 Hantek CSV capture.")
    parser.add_argument("csv_path", nargs="?", help="Dual CSV path. Defaults to newest dual capture.")
    parser.add_argument("--project-root", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--expected-frequency", type=float, default=1000.0)
    parser.add_argument("--frequency-tolerance-pct", type=float, default=5.0)
    parser.add_argument("--max-tjit-pct", type=float, default=2.0)
    parser.add_argument("--max-time-step-error-pct", type=float, default=1.0)
    parser.add_argument("--min-edges", type=int, default=3)
    args = parser.parse_args()

    project_root = Path(args.project_root).expanduser().resolve()
    path = Path(args.csv_path).expanduser().resolve() if args.csv_path else latest_dual_csv(project_root)
    time_s, ch1, ch2 = read_dual_csv(path)
    timing = time_metrics(time_s)
    ch1_metrics = edge_metrics(time_s, ch1)
    ch2_metrics = edge_metrics(time_s, ch2)

    print(f"csv: {path}")
    print_metrics("timing", timing)
    print_metrics("CH1", ch1_metrics)
    print_metrics("CH2", ch2_metrics)

    failures: list[str] = []
    if int(timing["non_positive_steps"]) > 0:
        failures.append(f"timing: {timing['non_positive_steps']} non-positive steps")
    if float(timing["max_step_error_pct"]) > args.max_time_step_error_pct:
        failures.append(
            f"timing: max step error {timing['max_step_error_pct']:.3g}% "
            f"> {args.max_time_step_error_pct:.3g}%"
        )
    failures.extend(validate_channel("CH1", ch1_metrics, args))
    failures.extend(validate_channel("CH2", ch2_metrics, args))

    if failures:
        print("validation: FAIL")
        for failure in failures:
            print(f"  - {failure}")
        return 2
    print("validation: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
