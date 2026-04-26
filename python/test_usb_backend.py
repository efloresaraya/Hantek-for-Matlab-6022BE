"""Unit tests for the direct Hantek USB backend.

These tests do not require the oscilloscope or PyUSB/libusb. Hardware tests are
run explicitly with `python/test_connection.py --mode usb`.
"""

from __future__ import annotations

import unittest
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))

from diagnostic_logger import DiagnosticLogger, NullDiagnosticLogger
from hantek_usb_backend import (
    FIRMWARE_SHA256,
    Hantek6022USBBackend,
    SampleRateSetting,
    calibration_frequency_code,
    convert_raw_capture,
    convert_raw_channels,
    firmware_path,
    parse_intel_hex,
    select_sample_rate,
    sha256_file,
)
from signal_utils import make_capture
from software_calibration import apply_software_calibration, load_software_calibration


class FakeUSBDevice:
    def __init__(self) -> None:
        self.control_calls: list[tuple[int, int, int, int, bytes, int | None]] = []

    def ctrl_transfer(self, bmRequestType, bRequest, wValue=0, wIndex=0, data_or_wLength=None, timeout=None):
        payload = bytes(data_or_wLength or b"")
        self.control_calls.append((bmRequestType, bRequest, wValue, wIndex, payload, timeout))
        return len(payload)


class FakeReadDevice(FakeUSBDevice):
    def __init__(self, total_bytes: int) -> None:
        super().__init__()
        self.total_bytes = total_bytes
        self.read_calls: list[int] = []

    def read(self, endpoint, size_or_buffer, timeout=None):
        self.read_calls.append(int(size_or_buffer))
        size = min(int(size_or_buffer), self.total_bytes)
        self.total_bytes -= size
        return bytes([0x80]) * size


class HantekUSBBackendTests(unittest.TestCase):
    def test_firmware_hash_matches_allowlist(self) -> None:
        path = firmware_path(Path(__file__).resolve().parents[1])
        self.assertEqual(sha256_file(path), FIRMWARE_SHA256)

    def test_parse_intel_hex_segments_are_internal_fx2lp(self) -> None:
        path = firmware_path(Path(__file__).resolve().parents[1])
        segments = parse_intel_hex(path)
        self.assertGreater(len(segments), 1)
        self.assertEqual(sum(len(segment.data) for segment in segments), 6924)
        self.assertLessEqual(max(segment.address + len(segment.data) for segment in segments), 0x4000)
        self.assertTrue(all(len(segment.data) <= 1023 for segment in segments))

    def test_select_sample_rate_1mhz(self) -> None:
        setting = select_sample_rate(1_000_000.0, channel_count=1)
        self.assertEqual(setting.sample_id, 10)
        self.assertEqual(setting.index, 12)
        self.assertEqual(setting.oversampling, 10)

    def test_select_sample_rate_rejects_unsupported(self) -> None:
        with self.assertRaises(ValueError):
            select_sample_rate(1_234_567.0, channel_count=1)

    def test_control_write_uses_vendor_out_request(self) -> None:
        fake = FakeUSBDevice()
        Hantek6022USBBackend._control_write(fake, 0xE4, [1])
        self.assertEqual(fake.control_calls, [(0x40, 0xE4, 0, 0, b"\x01", 500)])

    def test_calibration_frequency_code_matches_openhantek_mapping(self) -> None:
        self.assertEqual(calibration_frequency_code(1000), 1)
        self.assertEqual(calibration_frequency_code(100), 0)
        self.assertEqual(calibration_frequency_code(500), 150)
        self.assertEqual(calibration_frequency_code(1200), 212)

    def test_configure_sets_calibration_output_to_1khz(self) -> None:
        fake = FakeUSBDevice()
        backend = Hantek6022USBBackend(logger=NullDiagnosticLogger())
        backend.device = fake
        setting = SampleRateSetting(sample_rate=10_000_000.0, sample_id=10, oversampling=1, index=15)
        backend._configure(channel_count=2, setting=setting, gain_index=5, gain_value=1)
        self.assertIn((0x40, 0xE6, 0, 0, b"\x01", 500), fake.control_calls)

    def test_configure_sends_samplerate_before_channel_count(self) -> None:
        fake = FakeUSBDevice()
        backend = Hantek6022USBBackend(logger=NullDiagnosticLogger())
        backend.device = fake
        setting = SampleRateSetting(sample_rate=10_000_000.0, sample_id=10, oversampling=1, index=15)
        backend._configure(channel_count=2, setting=setting, gain_index=5, gain_value=1)
        requests = [call[1] for call in fake.control_calls]
        self.assertLess(requests.index(0xE2), requests.index(0xE4))

    def test_bulk_read_requests_large_contiguous_transfer(self) -> None:
        fake = FakeReadDevice(total_bytes=204_800)
        backend = Hantek6022USBBackend(logger=NullDiagnosticLogger())
        backend.device = fake
        data = backend._read_exact(204_800)
        self.assertEqual(len(data), 204_800)
        self.assertEqual(fake.read_calls, [204_800])

    def test_diagnostic_logger_writes_status_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            log_path = Path(tmpdir) / "diag.log"
            logger = DiagnosticLogger(project_root=tmpdir, log_path=log_path, echo=False)
            logger.ok("step ok", detail="value")
            text = log_path.read_text(encoding="utf-8")
            self.assertIn("diagnostic logger started", text)
            self.assertIn("[OK] step ok", text)
            self.assertIn("detail=value", text)

    def test_convert_raw_capture_applies_offset_scale_and_oversampling(self) -> None:
        setting = SampleRateSetting(sample_rate=1_000_000.0, sample_id=10, oversampling=2, index=12)
        raw = bytes([0x80, 0x80, 0x80 + 25, 0x80 + 25])
        capture = convert_raw_capture(
            raw=raw,
            setting=setting,
            n_samples=2,
            channel_count=1,
            channel=1,
            gain_index=5,
        )
        self.assertEqual(capture["n_samples"], 2)
        self.assertAlmostEqual(capture["voltage"][0], 0.0)
        self.assertAlmostEqual(capture["voltage"][1], 25 / 24.75)

    def test_convert_raw_capture_selects_ch2_from_interleaved_samples(self) -> None:
        setting = SampleRateSetting(sample_rate=1_000_000.0, sample_id=10, oversampling=2, index=12)
        raw = bytes(
            [
                0x80,
                0x80 + 10,
                0x80,
                0x80 + 10,
                0x80,
                0x80 + 20,
                0x80,
                0x80 + 20,
            ]
        )
        capture = convert_raw_capture(
            raw=raw,
            setting=setting,
            n_samples=2,
            channel_count=2,
            channel=2,
            gain_index=5,
        )
        self.assertEqual(capture["channel"], 2)
        self.assertEqual(capture["n_samples"], 2)
        self.assertAlmostEqual(capture["voltage"][0], 10 / 24.75)
        self.assertAlmostEqual(capture["voltage"][1], 20 / 24.75)

    def test_convert_raw_channels_returns_both_interleaved_channels(self) -> None:
        setting = SampleRateSetting(sample_rate=1_000_000.0, sample_id=10, oversampling=1, index=12)
        raw = bytes([0x80 + 1, 0x80 + 10, 0x80 + 2, 0x80 + 20])
        channels = convert_raw_channels(
            raw=raw,
            setting=setting,
            n_samples=2,
            channel_count=2,
            gain_index=5,
        )
        self.assertAlmostEqual(channels[1][0], 1 / 24.75)
        self.assertAlmostEqual(channels[1][1], 2 / 24.75)
        self.assertAlmostEqual(channels[2][0], 10 / 24.75)
        self.assertAlmostEqual(channels[2][1], 20 / 24.75)

    def test_software_calibration_file_loads(self) -> None:
        path = Path(__file__).resolve().parents[1] / "data" / "software_calibration.json"
        config = load_software_calibration(path)
        self.assertIn("ch1", config["channels"])
        self.assertIn("ch2", config["channels"])

    def test_apply_software_calibration_adjusts_voltage_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            calibration_path = Path(tmpdir) / "software_calibration.json"
            calibration_path.write_text(
                """{
  "schema": "hantek6022be-software-calibration-v1",
  "channels": {
    "ch1": {"enabled": true, "gain": 2.0, "offset_v": -1.0}
  }
}
""",
                encoding="utf-8",
            )
            capture = make_capture(
                time_s=[0.0, 1.0],
                voltage_v=[0.0, 1.5],
                sample_rate=1.0,
                channel=1,
                source="usb",
            )
            corrected = apply_software_calibration(capture, calibration_path=calibration_path)

        self.assertEqual(corrected["voltage"], [-1.0, 2.0])
        self.assertTrue(corrected["calibration_applied"])
        self.assertEqual(corrected["calibration_gain"], 2.0)
        self.assertEqual(corrected["calibration_offset_v"], -1.0)
        self.assertIn("software_calibration", corrected["metadata"])


if __name__ == "__main__":
    unittest.main()
