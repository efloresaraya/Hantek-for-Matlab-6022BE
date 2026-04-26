"""Signal simulator for the Hantek 6022BE MATLAB toolkit."""

from __future__ import annotations

import numpy as np

from signal_utils import CaptureDict, make_capture


def acquire(
    channel: int = 1,
    sample_rate: float = 1_000_000.0,
    n_samples: int = 2048,
    frequency: float = 1_000.0,
    amplitude: float = 1.0,
    offset: float = 0.0,
    phase: float = 0.0,
    noise_rms: float = 0.01,
    waveform: str = "sine",
) -> CaptureDict:
    """Generate a deterministic test capture."""

    if sample_rate <= 0:
        raise ValueError("sample_rate debe ser mayor que cero")
    if n_samples <= 0:
        raise ValueError("n_samples debe ser mayor que cero")

    rng = np.random.default_rng(6022 + int(channel))
    time_s = np.arange(int(n_samples), dtype=float) / float(sample_rate)
    omega_t = 2.0 * np.pi * float(frequency) * time_s + float(phase)

    if waveform == "sine":
        voltage = offset + amplitude * np.sin(omega_t)
    elif waveform == "square":
        voltage = offset + amplitude * np.sign(np.sin(omega_t))
    elif waveform == "triangle":
        cycles = (frequency * time_s + phase / (2.0 * np.pi)) % 1.0
        voltage = offset + amplitude * (4.0 * np.abs(cycles - 0.5) - 1.0)
    else:
        raise ValueError(f"waveform no soportado: {waveform}")

    if noise_rms > 0:
        voltage = voltage + rng.normal(0.0, float(noise_rms), size=time_s.shape)

    return make_capture(
        time_s=time_s,
        voltage_v=voltage,
        sample_rate=sample_rate,
        channel=channel,
        source="simulator",
        metadata={
            "frequency": float(frequency),
            "amplitude": float(amplitude),
            "offset": float(offset),
            "noise_rms": float(noise_rms),
            "waveform": waveform,
        },
    )


if __name__ == "__main__":
    capture = acquire()
    print(
        f"simulator OK: {capture['n_samples']} samples, "
        f"fs={capture['sample_rate']} Hz, source={capture['source']}"
    )

