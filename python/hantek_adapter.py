"""Unified acquisition adapter for simulator, CSV, USB, and OpenHantek modes."""

from __future__ import annotations

from pathlib import Path

from hantek_simulator import acquire as acquire_simulated
from hantek_usb_backend import Hantek6022USBBackend
from openhantek_adapter import OpenHantekAdapter
from signal_utils import CaptureDict, read_csv_capture
from software_calibration import apply_software_calibration


SUPPORTED_MODES = {"simulator", "csv", "usb", "openhantek"}


class HantekAdapter:
    def __init__(
        self,
        mode: str = "simulator",
        csv_path: str | Path | None = None,
        project_root: str | Path | None = None,
        openhantek_binary: str | Path | None = None,
        openhantek_capture_template: str | None = None,
        volts_per_div: float = 1.0,
        debug_log_path: str | Path | None = None,
        debug_echo: bool = True,
        apply_calibration: bool = False,
        calibration_path: str | Path | None = None,
    ) -> None:
        self.mode = mode.lower().strip()
        if self.mode not in SUPPORTED_MODES:
            raise ValueError(f"Modo no soportado: {mode}. Use uno de: {sorted(SUPPORTED_MODES)}")

        self.csv_path = Path(csv_path).expanduser().resolve() if csv_path else None
        self.project_root = Path(project_root).expanduser().resolve() if project_root else Path(__file__).resolve().parents[1]
        self.openhantek_binary = openhantek_binary
        self.openhantek_capture_template = openhantek_capture_template
        self.volts_per_div = float(volts_per_div)
        self.debug_log_path = debug_log_path
        self.debug_echo = bool(debug_echo)
        self.apply_calibration = bool(apply_calibration)
        self.calibration_path = Path(calibration_path).expanduser().resolve() if calibration_path else None

    def acquire(
        self,
        channel: int = 1,
        sample_rate: float = 1_000_000.0,
        n_samples: int = 2048,
        **kwargs: object,
    ) -> CaptureDict:
        if self.mode == "simulator":
            return acquire_simulated(
                channel=channel,
                sample_rate=sample_rate,
                n_samples=n_samples,
                frequency=float(kwargs.get("frequency", 1_000.0)),
                amplitude=float(kwargs.get("amplitude", 1.0)),
                offset=float(kwargs.get("offset", 0.0)),
                noise_rms=float(kwargs.get("noise_rms", 0.01)),
                waveform=str(kwargs.get("waveform", "sine")),
            )

        if self.mode == "csv":
            csv_path = kwargs.get("csv_path") or self.csv_path
            if csv_path is None:
                raise ValueError("mode='csv' requiere csv_path.")
            capture = read_csv_capture(csv_path, channel=channel, sample_rate=sample_rate, n_samples=n_samples)
            return self._maybe_apply_calibration(capture, kwargs)

        if self.mode == "usb":
            adapter = Hantek6022USBBackend(
                project_root=self.project_root,
                debug_log_path=self.debug_log_path,
                debug_echo=self.debug_echo,
            )
            try:
                capture = adapter.acquire(
                    channel=channel,
                    sample_rate=sample_rate,
                    n_samples=n_samples,
                    volts_per_div=float(kwargs.get("volts_per_div", self.volts_per_div)),
                )
                return self._maybe_apply_calibration(capture, kwargs)
            finally:
                adapter.close()

        adapter = OpenHantekAdapter(
            project_root=self.project_root,
            binary_path=self.openhantek_binary,
            capture_command_template=self.openhantek_capture_template,
        )
        capture = adapter.acquire(channel=channel, sample_rate=sample_rate, n_samples=n_samples)
        return self._maybe_apply_calibration(capture, kwargs)

    def _maybe_apply_calibration(self, capture: CaptureDict, kwargs: dict[str, object]) -> CaptureDict:
        requested = bool(kwargs.get("apply_calibration", self.apply_calibration))
        if not requested:
            return capture
        calibration_path = kwargs.get("calibration_path") or self.calibration_path
        return apply_software_calibration(
            capture,
            project_root=self.project_root,
            calibration_path=calibration_path,
        )


def acquire(
    mode: str = "simulator",
    channel: int = 1,
    sample_rate: float = 1_000_000.0,
    n_samples: int = 2048,
    csv_path: str | Path | None = None,
    project_root: str | Path | None = None,
    openhantek_binary: str | Path | None = None,
    openhantek_capture_template: str | None = None,
    volts_per_div: float = 1.0,
    debug_log_path: str | Path | None = None,
    debug_echo: bool = True,
    apply_calibration: bool = False,
    calibration_path: str | Path | None = None,
    **kwargs: object,
) -> CaptureDict:
    adapter = HantekAdapter(
        mode=mode,
        csv_path=csv_path,
        project_root=project_root,
        openhantek_binary=openhantek_binary,
        openhantek_capture_template=openhantek_capture_template,
        volts_per_div=volts_per_div,
        debug_log_path=debug_log_path,
        debug_echo=debug_echo,
        apply_calibration=apply_calibration,
        calibration_path=calibration_path,
    )
    return adapter.acquire(channel=channel, sample_rate=sample_rate, n_samples=n_samples, **kwargs)
