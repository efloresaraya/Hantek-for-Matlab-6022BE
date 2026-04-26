"""Template for a future direct Hantek/OpenHantek backend.

Use this file when there is a stable C/C++ API, shared library, or dedicated
CLI that can be called programmatically. The current project deliberately keeps
this as a template to avoid guessing the USB protocol from scratch.
"""

from __future__ import annotations

from signal_utils import CaptureDict


class HantekBackendTemplate:
    """Interface sketch for a future direct backend."""

    def __init__(self, device_id: str | None = None) -> None:
        self.device_id = device_id

    def open(self) -> None:
        raise NotImplementedError("Implementar apertura de dispositivo o biblioteca compartida.")

    def close(self) -> None:
        raise NotImplementedError("Implementar cierre/liberacion del backend.")

    def configure(self, channel: int, sample_rate: float, n_samples: int) -> None:
        raise NotImplementedError("Implementar configuracion de canal, muestreo y buffer.")

    def acquire(self, channel: int, sample_rate: float, n_samples: int) -> CaptureDict:
        raise NotImplementedError(
            "Conecte aqui una API C/C++, ctypes/cffi, pybind11 o CLI real de OpenHantek6022."
        )

