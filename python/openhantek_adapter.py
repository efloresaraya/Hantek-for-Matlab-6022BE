"""Safe adapter around the local OpenHantek6022 source tree.

This module does not assume that OpenHantek6022 exposes a Python API or a
headless capture CLI. It detects the source folder, looks for common build
outputs, and refuses to execute OpenHantek binaries. The hardware path for
this project is the direct `usb` backend.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable

from signal_utils import CaptureDict


NO_COMPATIBLE_CLI_MESSAGE = (
    "OpenHantek6022 fue encontrado, pero no se detectó una interfaz de línea "
    "de comandos compatible. Use modo csv o simulator, o adapte "
    "openhantek_adapter.py según la API/binario disponible."
)


class OpenHantekAdapter:
    """Detection-first OpenHantek6022 adapter."""

    def __init__(
        self,
        project_root: str | Path | None = None,
        binary_path: str | Path | None = None,
        capture_command_template: str | Iterable[str] | None = None,
        timeout_s: float = 30.0,
    ) -> None:
        self.project_root = Path(project_root).expanduser().resolve() if project_root else self._default_project_root()
        self.manual_binary_path = Path(binary_path).expanduser().resolve() if binary_path else None
        self.capture_command_template = None
        self.timeout_s = float(timeout_s)

    @staticmethod
    def _default_project_root() -> Path:
        return Path(__file__).resolve().parents[1]

    def find_openhantek_folder(self) -> Path | None:
        """Return the OpenHantek6022 repository root, if present."""

        candidates = [
            self.project_root / "OpenHantek6022",
            self.project_root / "OpenHantek6022" / "OpenHantek6022-main",
            self.project_root,
        ]

        for candidate in candidates:
            repo = self._as_repo_root(candidate)
            if repo:
                return repo

        wrapper = self.project_root / "OpenHantek6022"
        if wrapper.exists():
            for child in wrapper.iterdir():
                repo = self._as_repo_root(child)
                if repo:
                    return repo
        return None

    @staticmethod
    def _as_repo_root(path: Path) -> Path | None:
        if not path.exists() or not path.is_dir():
            return None
        if (path / "CMakeLists.txt").exists() and (path / "openhantek").is_dir():
            return path.resolve()
        return None

    def find_openhantek_binary(self) -> Path | None:
        """Return a likely OpenHantek executable path, if one is built."""

        if self.manual_binary_path:
            manual = self._normalize_binary_path(self.manual_binary_path)
            if manual and manual.is_file() and os.access(manual, os.X_OK):
                return manual

        folder = self.find_openhantek_folder()
        if folder is None:
            return None

        common_paths = [
            folder / "build" / "openhantek" / "OpenHantek",
            folder / "build" / "openhantek" / "OpenHantek.app",
            folder / "build" / "openhantek" / "OpenHantek.app" / "Contents" / "MacOS" / "OpenHantek",
            folder / "cmake-build-release" / "openhantek" / "OpenHantek",
            folder / "cmake-build-debug" / "openhantek" / "OpenHantek",
            folder / "openhantek" / "OpenHantek",
            folder / "OpenHantek",
        ]
        for candidate in common_paths:
            normalized = self._normalize_binary_path(candidate)
            if normalized and normalized.is_file() and os.access(normalized, os.X_OK):
                return normalized

        for candidate in folder.glob("**/OpenHantek.app/Contents/MacOS/OpenHantek"):
            if candidate.exists() and os.access(candidate, os.X_OK):
                return candidate.resolve()
        for candidate in folder.glob("**/OpenHantek"):
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate.resolve()
        return None

    @staticmethod
    def _normalize_binary_path(path: Path) -> Path | None:
        if path.suffix == ".app":
            executable = path / "Contents" / "MacOS" / "OpenHantek"
            return executable.resolve()
        return path.resolve()

    def is_available(self) -> bool:
        """OpenHantek execution is disabled by policy."""

        return False

    def capture_to_csv(
        self,
        channel: int = 1,
        sample_rate: float = 1_000_000.0,
        n_samples: int = 2048,
        output_path: str | Path = "data/raw/openhantek_capture.csv",
    ) -> Path:
        """Refuse OpenHantek execution; use `mode="usb"` or `mode="csv"`."""

        folder = self.find_openhantek_folder()
        if folder is None:
            raise RuntimeError("No se encontro la carpeta OpenHantek6022 dentro del proyecto.")

        raise RuntimeError(
            f"{NO_COMPATIBLE_CLI_MESSAGE} "
            "Politica de seguridad: este toolkit no ejecuta binarios de OpenHantek. "
            "Use mode='usb' para hardware fisico o mode='csv' para archivos existentes."
        )

    def acquire(
        self,
        channel: int = 1,
        sample_rate: float = 1_000_000.0,
        n_samples: int = 2048,
    ) -> CaptureDict:
        """OpenHantek execution is disabled; use the direct USB backend."""

        self.capture_to_csv(channel, sample_rate, n_samples)

    def diagnostic_status(self) -> dict[str, object]:
        folder = self.find_openhantek_folder()
        binary = self.find_openhantek_binary()
        return {
            "project_root": str(self.project_root),
            "openhantek_folder": str(folder) if folder else None,
            "openhantek_binary": str(binary) if binary else None,
            "capture_template_configured": False,
            "compatible_capture_cli": False,
            "available": False,
            "execution_policy": "disabled; use mode='usb'",
        }


if __name__ == "__main__":
    adapter = OpenHantekAdapter()
    for key, value in adapter.diagnostic_status().items():
        print(f"{key}: {value}")
