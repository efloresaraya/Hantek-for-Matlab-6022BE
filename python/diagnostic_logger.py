"""Small diagnostic logger for hardware bring-up sessions."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from time import monotonic
from typing import Any


class DiagnosticLogger:
    """Write timestamped status lines to console and a log file."""

    def __init__(
        self,
        project_root: str | Path,
        log_path: str | Path | None = None,
        echo: bool = True,
        enabled: bool = True,
        prefix: str = "hantek_usb",
    ) -> None:
        self.project_root = Path(project_root).expanduser().resolve()
        self.echo = bool(echo)
        self.enabled = bool(enabled)
        self.started = monotonic()
        if log_path is None:
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            self.path = self.project_root / "data" / "logs" / f"{prefix}_{stamp}.log"
        else:
            self.path = Path(log_path).expanduser().resolve()

        if self.enabled:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.event("INFO", "diagnostic logger started", log_path=str(self.path))

    def event(self, level: str, message: str, **fields: Any) -> None:
        if not self.enabled:
            return
        elapsed = monotonic() - self.started
        timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
        extra = ""
        if fields:
            pairs = [f"{key}={self._format_value(value)}" for key, value in sorted(fields.items())]
            extra = " | " + " ".join(pairs)
        line = f"{timestamp} +{elapsed:08.3f}s [{level.upper()}] {message}{extra}"
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
        if self.echo:
            print(line, flush=True)

    def info(self, message: str, **fields: Any) -> None:
        self.event("INFO", message, **fields)

    def ok(self, message: str, **fields: Any) -> None:
        self.event("OK", message, **fields)

    def warn(self, message: str, **fields: Any) -> None:
        self.event("WARN", message, **fields)

    def error(self, message: str, **fields: Any) -> None:
        self.event("ERROR", message, **fields)

    @staticmethod
    def _format_value(value: Any) -> str:
        text = str(value)
        if any(ch.isspace() for ch in text):
            return repr(text)
        return text


class NullDiagnosticLogger:
    """Logger-compatible object that discards all events."""

    path: Path | None = None

    def event(self, level: str, message: str, **fields: Any) -> None:
        return

    def info(self, message: str, **fields: Any) -> None:
        return

    def ok(self, message: str, **fields: Any) -> None:
        return

    def warn(self, message: str, **fields: Any) -> None:
        return

    def error(self, message: str, **fields: Any) -> None:
        return
