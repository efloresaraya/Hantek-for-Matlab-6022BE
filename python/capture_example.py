"""Example capture script for simulator, CSV, USB, or OpenHantek modes."""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path

from hantek_adapter import HantekAdapter
from signal_utils import write_csv_capture


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture data using the Hantek toolkit adapter.")
    parser.add_argument("--mode", choices=["simulator", "csv", "usb", "openhantek"], default="simulator")
    parser.add_argument("--channel", type=int, default=1)
    parser.add_argument("--sample-rate", type=float, default=1_000_000.0)
    parser.add_argument("--n-samples", type=int, default=2048)
    parser.add_argument("--volts-per-div", type=float, default=1.0)
    parser.add_argument("--csv-path", help="Input CSV path for mode=csv.")
    parser.add_argument("--openhantek-binary", help="Manual path to OpenHantek binary or .app.")
    parser.add_argument("--output", default="data/examples/simulator_capture.csv")
    parser.add_argument("--log-path", help="Optional diagnostic log path for mode=usb.")
    parser.add_argument("--quiet-log", action="store_true", help="Write USB diagnostic log without echoing each step.")
    parser.add_argument("--apply-calibration", action="store_true", help="Apply local software calibration from data/software_calibration.json.")
    parser.add_argument("--calibration-path", help="Optional software calibration JSON path.")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    debug_log_path = args.log_path
    if args.mode == "usb" and debug_log_path is None:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        debug_log_path = str(project_root / "data" / "logs" / f"hantek_usb_capture_{stamp}.log")
    adapter = HantekAdapter(
        mode=args.mode,
        csv_path=args.csv_path,
        project_root=project_root,
        openhantek_binary=args.openhantek_binary,
        debug_log_path=debug_log_path,
        debug_echo=not args.quiet_log,
        apply_calibration=args.apply_calibration,
        calibration_path=args.calibration_path,
    )
    try:
        capture = adapter.acquire(
            channel=args.channel,
            sample_rate=args.sample_rate,
            n_samples=args.n_samples,
            volts_per_div=args.volts_per_div,
        )
        output = write_csv_capture(capture, project_root / args.output)
        print(f"capture: {capture['source']} -> {output} ({capture['n_samples']} samples)")
        if args.mode == "usb":
            print(f"diagnostic log: {debug_log_path}")
        return 0
    except Exception as exc:
        print(f"capture ERROR: {exc}")
        if args.mode == "usb":
            print(f"diagnostic log: {debug_log_path}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
