"""Software-only calibration helpers for Hantek 6022BE captures.

The correction is intentionally local and reversible:

    corrected_voltage = raw_voltage * gain + offset_v

No command is sent to the oscilloscope and no EEPROM/calibration memory is
written. The JSON file is plain text so each coefficient can be audited.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from signal_utils import CaptureDict


SCHEMA = "hantek6022be-software-calibration-v1"
DEFAULT_CALIBRATION_RELATIVE_PATH = Path("data") / "software_calibration.json"


def default_calibration_path(project_root: str | Path | None = None) -> Path:
    if project_root is None:
        project_root = Path(__file__).resolve().parents[1]
    return Path(project_root).expanduser().resolve() / DEFAULT_CALIBRATION_RELATIVE_PATH


def load_software_calibration(path: str | Path) -> dict[str, Any]:
    calibration_path = Path(path).expanduser().resolve()
    if not calibration_path.exists():
        raise FileNotFoundError(f"No existe archivo de calibracion software: {calibration_path}")

    with calibration_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    if config.get("schema") != SCHEMA:
        raise ValueError(
            f"Archivo de calibracion incompatible: {calibration_path}. "
            f"schema esperado: {SCHEMA}"
        )
    if not isinstance(config.get("channels"), dict):
        raise ValueError(f"Archivo de calibracion sin tabla channels: {calibration_path}")
    return config


def channel_key(channel: object) -> str:
    try:
        channel_number = int(channel)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Canal invalido para calibracion software: {channel!r}") from exc
    if channel_number not in {1, 2}:
        raise ValueError(f"Canal invalido para calibracion software: CH{channel_number}")
    return f"ch{channel_number}"


def channel_calibration(config: dict[str, Any], channel: object) -> dict[str, Any]:
    key = channel_key(channel)
    channels = config.get("channels", {})
    entry = channels.get(key) or channels.get(key.upper()) or channels.get(str(key[-1]))
    if not isinstance(entry, dict):
        raise ValueError(f"No hay calibracion software para {key.upper()}")
    if not bool(entry.get("enabled", True)):
        raise ValueError(f"La calibracion software para {key.upper()} esta deshabilitada")
    return entry


def apply_software_calibration(
    capture: CaptureDict,
    project_root: str | Path | None = None,
    calibration_path: str | Path | None = None,
) -> CaptureDict:
    """Return a copy of capture with local software calibration applied."""

    path = Path(calibration_path).expanduser().resolve() if calibration_path else default_calibration_path(project_root)
    config = load_software_calibration(path)
    channel = capture.get("channel", 1)
    entry = channel_calibration(config, channel)

    gain = float(entry["gain"])
    offset_v = float(entry["offset_v"])
    raw_voltage = np.asarray(list(capture["voltage"]), dtype=float)
    corrected_voltage = raw_voltage * gain + offset_v

    result = dict(capture)
    result["voltage"] = [float(value) for value in corrected_voltage]
    result["calibration_applied"] = True
    result["calibration_gain"] = gain
    result["calibration_offset_v"] = offset_v
    result["calibration_path"] = str(path)

    metadata = dict(result.get("metadata") or {})
    metadata["software_calibration"] = {
        "applied": True,
        "schema": config.get("schema"),
        "path": str(path),
        "channel": channel_key(channel).upper(),
        "gain": gain,
        "offset_v": offset_v,
        "source": config.get("source", ""),
        "updated_at": config.get("updated_at", ""),
    }
    result["metadata"] = metadata
    return result
