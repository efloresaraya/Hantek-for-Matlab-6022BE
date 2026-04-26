"""Utilities for Hantek 6022BE capture data.

The functions in this module intentionally use simple Python containers at the
adapter boundary. MATLAB can consume Python lists more reliably than numpy
arrays, while Python callers can always convert lists back to arrays.
"""

from __future__ import annotations

import csv
import math
from pathlib import Path
from typing import Iterable

import numpy as np


CaptureDict = dict[str, object]


def make_capture(
    time_s: Iterable[float],
    voltage_v: Iterable[float],
    sample_rate: float | None,
    channel: int | str,
    source: str,
    metadata: dict[str, object] | None = None,
) -> CaptureDict:
    """Return a MATLAB-friendly capture dictionary."""

    time_list = [float(value) for value in time_s]
    voltage_list = [float(value) for value in voltage_v]
    capture: CaptureDict = {
        "time": time_list,
        "voltage": voltage_list,
        "sample_rate": float(sample_rate) if sample_rate else infer_sample_rate(time_list),
        "channel": channel,
        "source": source,
        "n_samples": len(voltage_list),
    }
    if metadata:
        capture["metadata"] = metadata
    return capture


def infer_sample_rate(time_s: list[float]) -> float:
    if len(time_s) < 2:
        return float("nan")
    dt = np.diff(np.asarray(time_s, dtype=float))
    dt = dt[np.isfinite(dt) & (dt > 0)]
    if dt.size == 0:
        return float("nan")
    return float(1.0 / np.median(dt))


def parse_number(text: str) -> float:
    """Parse numbers exported by OpenHantek in comma or dot decimal locales."""

    value = text.strip().strip('"').strip()
    if not value:
        return float("nan")

    # Locale case: decimal comma and no thousands separator.
    if "," in value and "." not in value:
        value = value.replace(",", ".")
    return float(value)


def sniff_dialect(path: Path) -> csv.Dialect:
    sample = path.read_text(encoding="utf-8-sig", errors="replace")[:4096]
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        class Fallback(csv.Dialect):
            delimiter = ","
            quotechar = '"'
            escapechar = None
            doublequote = True
            skipinitialspace = True
            lineterminator = "\n"
            quoting = csv.QUOTE_MINIMAL

        return Fallback


def normalize_header(header: str) -> str:
    return header.strip().strip('"').lower().replace(" ", "")


def find_time_column(headers: list[str]) -> int:
    normalized = [normalize_header(header) for header in headers]
    for idx, header in enumerate(normalized):
        if header in {"t/s", "time/s", "times", "time", "t"}:
            return idx
    return 0


def find_voltage_column(headers: list[str], channel: int | str) -> int:
    normalized = [normalize_header(header) for header in headers]
    channel_text = str(channel).lower().replace("channel", "ch").replace(" ", "")

    if isinstance(channel, int) or str(channel).isdigit():
        ch_num = int(channel)
        candidates = [
            f"ch{ch_num}/v",
            f"ch{ch_num}",
            f"channel{ch_num}/v",
            f"channel{ch_num}",
            f"c{ch_num}/v",
            f"c{ch_num}",
        ]
    else:
        candidates = [channel_text]

    for idx, header in enumerate(normalized):
        if any(candidate in header for candidate in candidates) and "/db" not in header:
            return idx

    # OpenHantek CSV starts with time, followed by voltage channels. If there is
    # no exact header match, use the requested 1-based channel after time.
    if isinstance(channel, int) or str(channel).isdigit():
        fallback = find_time_column(headers) + int(channel)
        if fallback < len(headers):
            return fallback

    for idx, header in enumerate(normalized):
        if idx != find_time_column(headers) and ("/v" in header or "volt" in header):
            return idx

    raise ValueError(
        f"No se encontro una columna de voltaje para channel={channel!r}. "
        f"Columnas disponibles: {headers}"
    )


def read_csv_capture(
    csv_path: str | Path,
    channel: int | str = 1,
    sample_rate: float | None = None,
    n_samples: int | None = None,
) -> CaptureDict:
    """Read an OpenHantek-style CSV export or a simple time/voltage CSV."""

    path = Path(csv_path).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"No existe el archivo CSV: {path}")

    dialect = sniff_dialect(path)
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
        reader = csv.reader(handle, dialect)
        rows = [row for row in reader if row and any(cell.strip() for cell in row)]

    if not rows:
        raise ValueError(f"El archivo CSV esta vacio: {path}")

    headers = [cell.strip().strip('"') for cell in rows[0]]
    time_idx = find_time_column(headers)
    voltage_idx = find_voltage_column(headers, channel)

    time_s: list[float] = []
    voltage_v: list[float] = []
    for row in rows[1:]:
        if len(row) <= max(time_idx, voltage_idx):
            continue
        try:
            t_value = parse_number(row[time_idx])
            v_value = parse_number(row[voltage_idx])
        except ValueError:
            continue
        if math.isfinite(t_value) and math.isfinite(v_value):
            time_s.append(t_value)
            voltage_v.append(v_value)
        if n_samples is not None and len(voltage_v) >= int(n_samples):
            break

    if not voltage_v:
        raise ValueError(f"No se pudieron leer muestras numericas desde: {path}")

    return make_capture(
        time_s=time_s,
        voltage_v=voltage_v,
        sample_rate=sample_rate,
        channel=channel,
        source="csv",
        metadata={"csv_path": str(path), "headers": headers},
    )


def write_csv_capture(capture: CaptureDict, output_path: str | Path) -> Path:
    """Write a capture dictionary as a simple CSV usable from MATLAB."""

    path = Path(output_path).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    channel = capture.get("channel", 1)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["t / s", f"CH{channel} / V"])
        for t_value, v_value in zip(capture["time"], capture["voltage"]):
            writer.writerow([f"{float(t_value):.10f}", f"{float(v_value):.10f}"])
    return path


def compute_fft(voltage_v: Iterable[float], sample_rate: float) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(list(voltage_v), dtype=float)
    if values.size == 0:
        return np.asarray([]), np.asarray([])
    values = values - np.nanmean(values)
    window = np.hanning(values.size) if values.size > 1 else np.ones(values.size)
    spectrum = np.fft.rfft(values * window)
    freq = np.fft.rfftfreq(values.size, d=1.0 / float(sample_rate))
    coherent_gain = np.sum(window) / values.size if values.size else 1.0
    magnitude = np.abs(spectrum) * 2.0 / max(values.size * coherent_gain, 1e-12)
    return freq, magnitude

