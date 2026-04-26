"""Direct USB backend for the Hantek 6022BE.

This module intentionally does not execute or link against OpenHantek. It uses
only locally inspected protocol constants and the firmware file already present
in the project tree.
"""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Protocol

import numpy as np

from diagnostic_logger import DiagnosticLogger, NullDiagnosticLogger
from signal_utils import CaptureDict, make_capture


LOADER_VID = 0x04B4
LOADER_PID = 0x6022
ACTIVE_VID = 0x04B5
ACTIVE_PID = 0x6022

ENDPOINT_IN = 0x86
DEFAULT_INTERFACE = 0

REQ_INTERNAL = 0xA0
REQ_SET_GAIN_CH1 = 0xE0
REQ_SET_GAIN_CH2 = 0xE1
REQ_SET_SAMPLERATE = 0xE2
REQ_START_SAMPLING = 0xE3
REQ_SET_NUM_CHANNELS = 0xE4
REQ_SET_CALFREQ = 0xE6

USB_TYPE_VENDOR_OUT = 0x40
CPUCS_FX2LP = 0xE600

FIRMWARE_RELATIVE_PATH = (
    "OpenHantek6022/OpenHantek6022-main/openhantek/res/firmware/dso6022be-firmware.hex"
)
FIRMWARE_SHA256 = "7773d886de861e2a95b159f103135b06391a6433adf0727d3d1e23aec9e65cfd"
DEFAULT_CALIBRATION_FREQUENCY_HZ = 1_000.0
BULK_READ_CHUNK_BYTES = 1024 * 1024

GAIN_LEVELS = [
    {"gain_value": 10, "vdiv": 20e-3, "scale": 250.0},
    {"gain_value": 10, "vdiv": 50e-3, "scale": 250.0},
    {"gain_value": 10, "vdiv": 100e-3, "scale": 250.0},
    {"gain_value": 5, "vdiv": 200e-3, "scale": 126.25},
    {"gain_value": 2, "vdiv": 500e-3, "scale": 49.50},
    {"gain_value": 1, "vdiv": 1.0, "scale": 24.75},
    {"gain_value": 1, "vdiv": 2.0, "scale": 24.75},
    {"gain_value": 1, "vdiv": 5.0, "scale": 24.75},
]


@dataclass(frozen=True)
class SampleRateSetting:
    sample_rate: float
    sample_id: int
    oversampling: int
    index: int

    @property
    def raw_sample_rate(self) -> float:
        return self.sample_rate * self.oversampling


SUPPORTED_SAMPLE_RATES: tuple[SampleRateSetting, ...] = tuple(
    SampleRateSetting(rate, sample_id, oversampling, index)
    for index, (rate, sample_id, oversampling) in enumerate(
        [
            (100.0, 102, 200),
            (200.0, 104, 200),
            (500.0, 110, 200),
            (1e3, 120, 200),
            (2e3, 140, 200),
            (5e3, 1, 200),
            (10e3, 1, 100),
            (20e3, 2, 100),
            (50e3, 5, 100),
            (100e3, 10, 100),
            (200e3, 10, 50),
            (500e3, 10, 20),
            (1e6, 10, 10),
            (2e6, 10, 5),
            (5e6, 10, 2),
            (10e6, 10, 1),
            (12e6, 12, 1),
            (15e6, 15, 1),
            (24e6, 24, 1),
            (30e6, 30, 1),
            (48e6, 48, 1),
        ]
    )
)


@dataclass(frozen=True)
class FirmwareSegment:
    address: int
    data: bytes


class USBDevice(Protocol):
    def ctrl_transfer(
        self,
        bmRequestType: int,
        bRequest: int,
        wValue: int = 0,
        wIndex: int = 0,
        data_or_wLength: bytes | int | None = None,
        timeout: int | None = None,
    ) -> int: ...

    def read(self, endpoint: int, size_or_buffer: int, timeout: int | None = None) -> bytes: ...


class HantekUSBError(RuntimeError):
    """Raised when the direct USB backend cannot complete a safe operation."""


def import_pyusb():
    try:
        import usb.core  # type: ignore
        import usb.util  # type: ignore
    except ImportError as exc:
        raise HantekUSBError(
            "PyUSB no esta instalado. Instale las dependencias con conda/pip y asegure libusb en macOS."
        ) from exc
    return usb.core, usb.util


def default_project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def firmware_path(project_root: str | Path | None = None) -> Path:
    root = Path(project_root).expanduser().resolve() if project_root else default_project_root()
    return root / FIRMWARE_RELATIVE_PATH


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_firmware(path: str | Path) -> Path:
    fw_path = Path(path).expanduser().resolve()
    if not fw_path.exists():
        raise HantekUSBError(f"No existe el firmware local esperado: {fw_path}")
    digest = sha256_file(fw_path)
    if digest != FIRMWARE_SHA256:
        raise HantekUSBError(
            "El firmware local no coincide con el SHA256 permitido. "
            f"Esperado={FIRMWARE_SHA256}, actual={digest}."
        )
    return fw_path


def parse_intel_hex(path: str | Path, max_segment_size: int = 1023) -> list[FirmwareSegment]:
    """Parse Intel HEX into contiguous write segments with checksum validation."""

    current_base = 0
    segments: list[FirmwareSegment] = []
    pending_addr: int | None = None
    pending = bytearray()

    def flush() -> None:
        nonlocal pending_addr, pending
        if pending_addr is not None and pending:
            segments.append(FirmwareSegment(pending_addr, bytes(pending)))
        pending_addr = None
        pending = bytearray()

    for line_no, raw_line in enumerate(Path(path).read_text(encoding="ascii").splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: falta ':'")
        try:
            record = bytes.fromhex(line[1:])
        except ValueError as exc:
            raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: hexadecimal corrupto") from exc
        if len(record) < 5:
            raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: registro demasiado corto")

        count = record[0]
        if len(record) != count + 5:
            raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: largo inconsistente")
        if sum(record) & 0xFF:
            raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: checksum incorrecto")

        offset = (record[1] << 8) | record[2]
        record_type = record[3]
        data = record[4 : 4 + count]

        if record_type == 0x00:
            absolute = current_base + offset
            if not is_fx2lp_internal_range(absolute, len(data)):
                raise HantekUSBError(
                    f"Firmware contiene direccion fuera de RAM interna FX2LP: 0x{absolute:04x}"
                )
            contiguous = pending_addr is not None and absolute == pending_addr + len(pending)
            fits = len(pending) + len(data) <= max_segment_size
            if not contiguous or not fits:
                flush()
                pending_addr = absolute
            pending.extend(data)
        elif record_type == 0x01:
            flush()
            return segments
        elif record_type == 0x02:
            flush()
            if count != 2:
                raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: base segment mal formada")
            current_base = ((data[0] << 8) | data[1]) << 4
        elif record_type == 0x04:
            flush()
            if count != 2:
                raise HantekUSBError(f"Intel HEX invalido en linea {line_no}: base linear mal formada")
            current_base = ((data[0] << 8) | data[1]) << 16
        else:
            raise HantekUSBError(f"Intel HEX no soportado en linea {line_no}: tipo {record_type}")

    flush()
    raise HantekUSBError("Intel HEX sin registro EOF")


def is_fx2lp_internal_range(address: int, length: int) -> bool:
    end = address + length
    return (0x0000 <= address and end <= 0x4000) or (0xE000 <= address and end <= 0xE200)


def select_sample_rate(sample_rate: float, channel_count: int = 1) -> SampleRateSetting:
    if channel_count not in {1, 2}:
        raise ValueError("channel_count debe ser 1 o 2")
    max_rate = 30e6 if channel_count == 1 else 15e6
    for setting in SUPPORTED_SAMPLE_RATES:
        if setting.sample_rate <= max_rate and round(setting.sample_rate) == round(float(sample_rate)):
            return setting
    supported = [int(s.sample_rate) for s in SUPPORTED_SAMPLE_RATES if s.sample_rate <= max_rate]
    raise ValueError(f"sample_rate no soportado: {sample_rate}. Valores soportados: {supported}")


def select_gain(volts_per_div: float) -> tuple[int, dict[str, float]]:
    for index, gain in enumerate(GAIN_LEVELS):
        if abs(gain["vdiv"] - float(volts_per_div)) <= max(1e-12, gain["vdiv"] * 1e-9):
            return index, gain
    supported = [gain["vdiv"] for gain in GAIN_LEVELS]
    raise ValueError(f"volts_per_div no soportado: {volts_per_div}. Valores soportados: {supported}")


def gross_raw_count(result_samples: int, oversampling: int) -> int:
    net = int(result_samples) * int(oversampling)
    return ((net + 1024) // 1024 + 2) * 1024


def calibration_frequency_code(frequency_hz: float = DEFAULT_CALIBRATION_FREQUENCY_HZ) -> int:
    frequency = float(frequency_hz)
    if frequency <= 0:
        raise ValueError("calibration frequency must be positive")
    if frequency < 1000:
        code = 100 + round(frequency / 10)
        if code == 110:
            code = 0
    elif frequency <= 5500 and int(frequency) % 1000:
        code = 200 + round(frequency / 100)
    else:
        code = round(frequency / 1000)
    if not 0 <= int(code) <= 255:
        raise ValueError(f"calibration frequency unsupported: {frequency_hz}")
    return int(code)


def convert_raw_capture(
    raw: bytes | bytearray | np.ndarray,
    setting: SampleRateSetting,
    n_samples: int,
    channel_count: int,
    channel: int,
    gain_index: int,
    adc_offset: float = 0x80,
) -> CaptureDict:
    if channel not in {1, 2}:
        raise ValueError("channel debe ser 1 o 2")
    if channel_count not in {1, 2}:
        raise ValueError("channel_count debe ser 1 o 2")
    if channel > channel_count:
        raise ValueError("channel no puede ser mayor que channel_count")

    channel_values = convert_raw_channels(
        raw=raw,
        setting=setting,
        n_samples=n_samples,
        channel_count=channel_count,
        gain_index=gain_index,
        adc_offset=adc_offset,
    )
    voltage = channel_values[channel]
    time_s = np.arange(int(n_samples), dtype=float) / float(setting.sample_rate)
    return make_capture(
        time_s=time_s,
        voltage_v=voltage,
        sample_rate=setting.sample_rate,
        channel=channel,
        source="usb",
        metadata={
            "raw_sample_rate": setting.raw_sample_rate,
            "oversampling": setting.oversampling,
            "sample_id": setting.sample_id,
            "sample_index": setting.index,
            "gain_index": gain_index,
            "volts_per_div": GAIN_LEVELS[gain_index]["vdiv"],
        },
    )


def convert_raw_channels(
    raw: bytes | bytearray | np.ndarray,
    setting: SampleRateSetting,
    n_samples: int,
    channel_count: int,
    gain_index: int,
    adc_offset: float = 0x80,
) -> dict[int, np.ndarray]:
    if channel_count not in {1, 2}:
        raise ValueError("channel_count debe ser 1 o 2")

    values = np.frombuffer(bytes(raw), dtype=np.uint8)
    if values.size % channel_count:
        values = values[: values.size - (values.size % channel_count)]
    raw_samples = values.reshape(-1, channel_count)
    needed_raw = int(n_samples) * setting.oversampling
    skip = max(0, raw_samples.shape[0] - needed_raw)
    voltage_scale = float(GAIN_LEVELS[gain_index]["scale"])
    channels: dict[int, np.ndarray] = {}
    for channel_index in range(channel_count):
        selected = raw_samples[skip:, channel_index]
        selected = selected[:needed_raw]
        if selected.size < needed_raw:
            raise HantekUSBError(f"Captura incompleta: {selected.size} muestras crudas de {needed_raw} esperadas")
        grouped = selected.astype(float).reshape(int(n_samples), setting.oversampling)
        averaged = grouped.mean(axis=1)
        channels[channel_index + 1] = (averaged - float(adc_offset)) / voltage_scale
    return channels


class Hantek6022USBBackend:
    def __init__(
        self,
        project_root: str | Path | None = None,
        timeout_ms: int = 1000,
        renumeration_timeout_s: float = 8.0,
        logger: DiagnosticLogger | NullDiagnosticLogger | None = None,
        debug_log_path: str | Path | None = None,
        debug_echo: bool = True,
    ) -> None:
        self.project_root = Path(project_root).expanduser().resolve() if project_root else default_project_root()
        self.timeout_ms = int(timeout_ms)
        self.renumeration_timeout_s = float(renumeration_timeout_s)
        self.device = None
        self.interface_number = DEFAULT_INTERFACE
        self._usb_core = None
        self._usb_util = None
        self.logger = logger or DiagnosticLogger(
            self.project_root,
            log_path=debug_log_path,
            echo=debug_echo,
        )

    def acquire(
        self,
        channel: int = 1,
        sample_rate: float = 1_000_000.0,
        n_samples: int = 20_000,
        volts_per_div: float = 1.0,
    ) -> CaptureDict:
        if channel not in {1, 2}:
            raise ValueError("channel debe ser 1 o 2")
        if n_samples <= 0:
            raise ValueError("n_samples debe ser mayor que cero")

        channel_count = 1 if channel == 1 else 2
        setting = select_sample_rate(sample_rate, channel_count=channel_count)
        gain_index, gain = select_gain(volts_per_div)
        self.logger.info(
            "usb acquisition requested",
            channel=channel,
            channel_count=channel_count,
            sample_rate=sample_rate,
            n_samples=n_samples,
            volts_per_div=volts_per_div,
            log_path=self.log_path,
        )
        self.logger.ok(
            "acquisition parameters accepted",
            raw_sample_rate=setting.raw_sample_rate,
            oversampling=setting.oversampling,
            sample_id=setting.sample_id,
            sample_index=setting.index,
            gain_index=gain_index,
        )

        self.ensure_active_device()
        assert self.device is not None

        self._configure(channel_count=channel_count, setting=setting, gain_index=gain_index, gain_value=int(gain["gain_value"]))
        raw_length = gross_raw_count(int(n_samples), setting.oversampling) * channel_count
        self.logger.info("starting sampling", raw_bytes=raw_length, endpoint=f"0x{ENDPOINT_IN:02x}")
        try:
            self._control_write(self.device, REQ_START_SAMPLING, [0x01])
            raw = self._read_exact(raw_length)
        finally:
            try:
                self._control_write(self.device, REQ_START_SAMPLING, [0x00])
                self.logger.ok("sampling stopped")
            except Exception:
                self.logger.warn("sampling stop command failed")

        capture = convert_raw_capture(
            raw=raw,
            setting=setting,
            n_samples=int(n_samples),
            channel_count=channel_count,
            channel=channel,
            gain_index=gain_index,
        )
        if isinstance(capture.get("metadata"), dict):
            capture["metadata"]["diagnostic_log"] = self.log_path
        self.logger.ok("capture converted", samples=capture["n_samples"], source=capture["source"])
        return capture

    def acquire_dual(
        self,
        sample_rate: float = 1_000_000.0,
        n_samples: int = 20_000,
        volts_per_div: float = 1.0,
    ) -> dict[str, object]:
        """Capture CH1 and CH2 from the same dual-channel USB block."""

        if n_samples <= 0:
            raise ValueError("n_samples debe ser mayor que cero")

        channel_count = 2
        setting = select_sample_rate(sample_rate, channel_count=channel_count)
        gain_index, gain = select_gain(volts_per_div)
        self.logger.info(
            "usb dual acquisition requested",
            channel_count=channel_count,
            sample_rate=sample_rate,
            n_samples=n_samples,
            volts_per_div=volts_per_div,
            log_path=self.log_path,
        )
        self.logger.ok(
            "dual acquisition parameters accepted",
            raw_sample_rate=setting.raw_sample_rate,
            oversampling=setting.oversampling,
            sample_id=setting.sample_id,
            sample_index=setting.index,
            gain_index=gain_index,
        )

        self.ensure_active_device()
        assert self.device is not None

        self._configure(channel_count=channel_count, setting=setting, gain_index=gain_index, gain_value=int(gain["gain_value"]))
        raw_length = gross_raw_count(int(n_samples), setting.oversampling) * channel_count
        self.logger.info("starting dual sampling", raw_bytes=raw_length, endpoint=f"0x{ENDPOINT_IN:02x}")
        try:
            self._control_write(self.device, REQ_START_SAMPLING, [0x01])
            raw = self._read_exact(raw_length)
        finally:
            try:
                self._control_write(self.device, REQ_START_SAMPLING, [0x00])
                self.logger.ok("dual sampling stopped")
            except Exception:
                self.logger.warn("dual sampling stop command failed")

        channels = convert_raw_channels(
            raw=raw,
            setting=setting,
            n_samples=int(n_samples),
            channel_count=channel_count,
            gain_index=gain_index,
        )
        time_s = np.arange(int(n_samples), dtype=float) / float(setting.sample_rate)
        capture = {
            "time": [float(value) for value in time_s],
            "ch1": [float(value) for value in channels[1]],
            "ch2": [float(value) for value in channels[2]],
            "sample_rate": setting.sample_rate,
            "n_samples": int(n_samples),
            "source": "usb_dual",
            "metadata": {
                "raw_sample_rate": setting.raw_sample_rate,
                "oversampling": setting.oversampling,
                "sample_id": setting.sample_id,
                "sample_index": setting.index,
                "gain_index": gain_index,
                "volts_per_div": GAIN_LEVELS[gain_index]["vdiv"],
                "diagnostic_log": self.log_path,
            },
        }
        self.logger.ok("dual capture converted", samples=capture["n_samples"], source=capture["source"])
        return capture

    @property
    def log_path(self) -> str | None:
        path = getattr(self.logger, "path", None)
        return str(path) if path else None

    def diagnostic_status(self) -> dict[str, object]:
        self.logger.info("diagnostic status requested")
        self._load_usb()
        active = self._find_device(ACTIVE_VID, ACTIVE_PID)
        loader = self._find_device(LOADER_VID, LOADER_PID)
        fw = firmware_path(self.project_root)
        status = {
            "loader_vid_pid": "04b4:6022",
            "active_vid_pid": "04b5:6022",
            "loader_present": loader is not None,
            "active_present": active is not None,
            "firmware_path": str(fw),
            "firmware_sha256_expected": FIRMWARE_SHA256,
            "firmware_sha256_actual": sha256_file(fw) if fw.exists() else None,
            "firmware_hash_ok": fw.exists() and sha256_file(fw) == FIRMWARE_SHA256,
            "log_path": self.log_path,
        }
        if status["loader_present"] or status["active_present"]:
            self.logger.ok(
                "device detection status",
                loader_present=status["loader_present"],
                active_present=status["active_present"],
            )
        else:
            self.logger.warn("device not detected", loader_present=False, active_present=False)
        if status["firmware_hash_ok"]:
            self.logger.ok("firmware hash ok", firmware_path=str(fw))
        else:
            self.logger.error("firmware hash missing or invalid", firmware_path=str(fw))
        return status

    def ensure_active_device(self) -> None:
        self.logger.info("ensuring active Hantek device")
        self._load_usb()
        active = self._find_device(ACTIVE_VID, ACTIVE_PID)
        if active is None:
            self.logger.warn("active device not present", vid_pid="04b5:6022")
            loader = self._find_device(LOADER_VID, LOADER_PID)
            if loader is None:
                self.logger.error("loader device not present", vid_pid="04b4:6022")
                raise HantekUSBError("No se detecto Hantek 6022BE en estado loader ni activo.")
            self.logger.ok("loader device found", vid_pid="04b4:6022")
            self._upload_firmware(loader)
            active = self._wait_for_active_device()
        else:
            self.logger.ok("active device found", vid_pid="04b5:6022")
        if active is None:
            self.logger.error("device did not renumerate", expected_vid_pid="04b5:6022")
            raise HantekUSBError("El Hantek no renumero a 04b5:6022 despues de cargar firmware.")
        self.device = active
        self.interface_number = self._claim_vendor_interface(active)
        self.logger.ok("active device claimed", interface=self.interface_number)

    def close(self) -> None:
        if self.device is None or self._usb_util is None:
            return
        try:
            self._usb_util.release_interface(self.device, self.interface_number)
            self.logger.ok("usb interface released", interface=self.interface_number)
        finally:
            self._usb_util.dispose_resources(self.device)
            self.device = None

    def _load_usb(self) -> None:
        if self._usb_core is None or self._usb_util is None:
            self.logger.info("loading PyUSB")
            try:
                self._usb_core, self._usb_util = import_pyusb()
            except Exception as exc:
                self.logger.error("PyUSB load failed", error=exc)
                raise
            self.logger.ok("PyUSB loaded")

    def _find_device(self, vid: int, pid: int):
        self._load_usb()
        self.logger.info("searching USB device", vid=f"0x{vid:04x}", pid=f"0x{pid:04x}")
        device = self._usb_core.find(idVendor=vid, idProduct=pid)
        if device is None:
            self.logger.warn("USB device not found", vid=f"0x{vid:04x}", pid=f"0x{pid:04x}")
        else:
            self.logger.ok("USB device found", vid=f"0x{vid:04x}", pid=f"0x{pid:04x}")
        return device

    def _upload_firmware(self, loader_device) -> None:
        self.logger.info("firmware upload requested")
        try:
            fw = verify_firmware(firmware_path(self.project_root))
        except Exception as exc:
            self.logger.error("firmware verification failed", error=exc)
            raise
        self.logger.ok("firmware SHA256 verified", firmware_path=str(fw), sha256=FIRMWARE_SHA256)
        try:
            segments = parse_intel_hex(fw)
        except Exception as exc:
            self.logger.error("firmware Intel HEX parse failed", error=exc)
            raise
        self.logger.ok("firmware Intel HEX parsed", segments=len(segments), bytes=sum(len(s.data) for s in segments))
        self._prepare_device(loader_device)
        interface = self._claim_vendor_interface(loader_device)
        try:
            self.logger.info("halting FX2LP CPU", address=f"0x{CPUCS_FX2LP:04x}")
            self._write_internal(loader_device, CPUCS_FX2LP, [0x01])
            total = len(segments)
            for index, segment in enumerate(segments, start=1):
                self._write_internal(loader_device, segment.address, segment.data)
                if index == 1 or index == total or index % 25 == 0:
                    self.logger.info("firmware segment written", segment=index, total=total, address=f"0x{segment.address:04x}", bytes=len(segment.data))
            self.logger.info("releasing FX2LP CPU", address=f"0x{CPUCS_FX2LP:04x}")
            self._write_internal(loader_device, CPUCS_FX2LP, [0x00])
            self.logger.ok("firmware upload completed")
        finally:
            try:
                self._usb_util.release_interface(loader_device, interface)
                self.logger.ok("loader interface released", interface=interface)
            finally:
                self._usb_util.dispose_resources(loader_device)

    def _wait_for_active_device(self):
        self.logger.info("waiting for device renumeration", timeout_s=self.renumeration_timeout_s)
        deadline = time.monotonic() + self.renumeration_timeout_s
        while time.monotonic() < deadline:
            active = self._find_device(ACTIVE_VID, ACTIVE_PID)
            if active is not None:
                self.logger.ok("renumeration complete", vid_pid="04b5:6022")
                return active
            time.sleep(0.25)
        self.logger.error("renumeration timeout", timeout_s=self.renumeration_timeout_s)
        return None

    def _prepare_device(self, device) -> None:
        try:
            device.set_configuration()
            self.logger.ok("usb configuration set")
        except Exception:
            # macOS/libusb often has the default configuration already active.
            self.logger.warn("usb set_configuration skipped or failed")

    def _claim_vendor_interface(self, device) -> int:
        self._prepare_device(device)
        interface_number = DEFAULT_INTERFACE
        try:
            config = device.get_active_configuration()
            for interface in config:
                descriptor = interface[(0, 0)]
                if getattr(descriptor, "bInterfaceClass", None) == 0xFF:
                    interface_number = int(descriptor.bInterfaceNumber)
                    break
        except Exception:
            interface_number = DEFAULT_INTERFACE
            self.logger.warn("could not inspect active configuration; using default interface", interface=interface_number)
        self.logger.info("claiming usb interface", interface=interface_number)
        try:
            self._usb_util.claim_interface(device, interface_number)
        except Exception as exc:
            self.logger.error("usb interface claim failed", interface=interface_number, error=exc)
            raise
        return interface_number

    @staticmethod
    def _control_write(device: USBDevice, request: int, data: Iterable[int] | bytes) -> None:
        payload = bytes(data)
        transferred = device.ctrl_transfer(
            USB_TYPE_VENDOR_OUT,
            int(request),
            0,
            0,
            payload,
            timeout=500,
        )
        if transferred != len(payload):
            raise HantekUSBError(f"Control transfer incompleto para request 0x{request:02x}")

    def _write_internal(self, device: USBDevice, address: int, data: Iterable[int] | bytes) -> None:
        payload = bytes(data)
        try:
            transferred = device.ctrl_transfer(
                USB_TYPE_VENDOR_OUT,
                REQ_INTERNAL,
                int(address) & 0xFFFF,
                int(address) >> 16,
                payload,
                timeout=self.timeout_ms,
            )
        except Exception as exc:
            self.logger.error("firmware control transfer failed", address=f"0x{address:04x}", bytes=len(payload), error=exc)
            raise
        if transferred != len(payload):
            self.logger.error("firmware control transfer incomplete", address=f"0x{address:04x}", expected=len(payload), actual=transferred)
            raise HantekUSBError(f"Escritura firmware incompleta en 0x{address:04x}")

    def _configure(self, channel_count: int, setting: SampleRateSetting, gain_index: int, gain_value: int) -> None:
        assert self.device is not None
        self.logger.info("configuring scope", channels=channel_count, gain_index=gain_index, gain_value=gain_value)
        try:
            self._control_write(self.device, REQ_SET_GAIN_CH1, [gain_value, gain_index])
            self._control_write(self.device, REQ_SET_GAIN_CH2, [gain_value, gain_index])
            self._control_write(self.device, REQ_SET_SAMPLERATE, [setting.sample_id, setting.index])
            self._control_write(self.device, REQ_SET_NUM_CHANNELS, [channel_count])
            cal_code = calibration_frequency_code(DEFAULT_CALIBRATION_FREQUENCY_HZ)
            self._control_write(self.device, REQ_SET_CALFREQ, [cal_code])
        except Exception as exc:
            self.logger.error("scope configuration failed", error=exc)
            raise
        self.logger.ok(
            "scope configured",
            sample_id=setting.sample_id,
            sample_index=setting.index,
            calibration_frequency_hz=DEFAULT_CALIBRATION_FREQUENCY_HZ,
        )

    def _read_exact(self, length: int) -> bytes:
        assert self.device is not None
        self.logger.info("reading USB bulk data", bytes=length, endpoint=f"0x{ENDPOINT_IN:02x}")
        chunks: list[bytes] = []
        remaining = int(length)
        received = 0
        while remaining > 0:
            request_size = min(remaining, BULK_READ_CHUNK_BYTES)
            chunk = self.device.read(ENDPOINT_IN, request_size, timeout=max(self.timeout_ms, 1000))
            chunk_bytes = bytes(chunk)
            if not chunk_bytes:
                self.logger.error("empty USB bulk read", received=received, remaining=remaining)
                raise HantekUSBError("Lectura USB vacia durante captura.")
            chunks.append(chunk_bytes)
            remaining -= len(chunk_bytes)
            received += len(chunk_bytes)
            if remaining == 0 or received == len(chunk_bytes) or received % (512 * 128) == 0:
                self.logger.info("USB bulk progress", received=received, remaining=remaining)
        self.logger.ok("USB bulk read complete", received=received)
        return b"".join(chunks)[:length]


def acquire(
    channel: int = 1,
    sample_rate: float = 1_000_000.0,
    n_samples: int = 20_000,
    project_root: str | Path | None = None,
    volts_per_div: float = 1.0,
    debug_log_path: str | Path | None = None,
    debug_echo: bool = True,
) -> CaptureDict:
    backend = Hantek6022USBBackend(project_root=project_root, debug_log_path=debug_log_path, debug_echo=debug_echo)
    try:
        return backend.acquire(
            channel=channel,
            sample_rate=sample_rate,
            n_samples=n_samples,
            volts_per_div=volts_per_div,
        )
    finally:
        backend.close()


if __name__ == "__main__":
    backend = Hantek6022USBBackend()
    for key, value in backend.diagnostic_status().items():
        print(f"{key}: {value}")
