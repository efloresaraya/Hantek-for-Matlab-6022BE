"""Quick diagnostics for the Hantek 6022BE MATLAB toolkit."""

from __future__ import annotations

import argparse
from pathlib import Path

from hantek_adapter import HantekAdapter
from openhantek_adapter import OpenHantekAdapter
from hantek_usb_backend import Hantek6022USBBackend


def main() -> int:
    parser = argparse.ArgumentParser(description="Test Hantek toolkit acquisition modes.")
    parser.add_argument("--mode", choices=["all", "simulator", "csv", "usb", "openhantek"], default="all")
    parser.add_argument("--csv", dest="csv_path", help="Optional CSV file to test csv mode.")
    parser.add_argument("--project-root", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--channel", type=int, default=1)
    parser.add_argument("--sample-rate", type=float, default=1_000_000.0)
    parser.add_argument("--n-samples", type=int, default=20_000)
    parser.add_argument("--log-path", help="Optional diagnostic log path for mode=usb.")
    parser.add_argument("--quiet-log", action="store_true", help="Write USB diagnostic log without echoing each step.")
    parser.add_argument("--apply-calibration", action="store_true", help="Apply local software calibration after USB capture.")
    parser.add_argument("--calibration-path", help="Optional software calibration JSON path.")
    args = parser.parse_args()

    if args.mode in {"all", "simulator"}:
        sim = HantekAdapter(mode="simulator").acquire(n_samples=16)
        print(f"simulator: OK ({sim['n_samples']} samples)")

    if args.mode in {"all", "csv"}:
        if args.csv_path:
            csv_capture = HantekAdapter(mode="csv", csv_path=args.csv_path).acquire(n_samples=16)
            print(f"csv: OK ({csv_capture['n_samples']} samples from {args.csv_path})")
        else:
            print("csv: skipped (use --csv path/to/capture.csv)")

    if args.mode in {"all", "openhantek"}:
        openhantek = OpenHantekAdapter(project_root=args.project_root)
        status = openhantek.diagnostic_status()
        print("openhantek:")
        for key, value in status.items():
            print(f"  {key}: {value}")
        if not status["available"]:
            print("  note: OpenHantek se mantiene solo como referencia/deteccion.")

    if args.mode == "usb":
        print("usb:")
        usb_backend = Hantek6022USBBackend(
            project_root=args.project_root,
            debug_log_path=args.log_path,
            debug_echo=not args.quiet_log,
        )
        try:
            print(f"  diagnostic_log: {usb_backend.log_path}")
            for key, value in usb_backend.diagnostic_status().items():
                print(f"  {key}: {value}")
            capture = usb_backend.acquire(
                channel=args.channel,
                sample_rate=args.sample_rate,
                n_samples=args.n_samples,
            )
            if args.apply_calibration:
                from software_calibration import apply_software_calibration

                capture = apply_software_calibration(
                    capture,
                    project_root=args.project_root,
                    calibration_path=args.calibration_path,
                )
            print(f"usb: OK ({capture['n_samples']} samples, fs={capture['sample_rate']} Hz)")
        except Exception as exc:
            print(f"usb: ERROR: {exc}")
            print(f"usb: diagnostic log: {usb_backend.log_path}")
            return 2
        finally:
            usb_backend.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
