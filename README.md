# Hantek 6022BE — MATLAB Toolkit

Acquire, calibrate and analyze signals from a **Hantek 6022BE** USB oscilloscope
directly from MATLAB — no OpenHantek, no compiled drivers.

```
Hantek 6022BE (USB)
      ↓
  PyUSB / libusb  (Python backend)
      ↓
  MATLAB bridge   (hantek_acquire / hantek_acquire_dual)
      ↓
  Live apps · FFT · Metrics · Calibration · Export
```

Tested on **macOS** (Apple Silicon and Intel) with MATLAB R2023b and Python 3.11.

---

## Features

| | |
|---|---|
| **Direct USB** | Firmware upload, bulk transfer, no OpenHantek dependency |
| **Single-channel live app** | CH1 or CH2, trigger, FFT, metrics, save |
| **Dual-channel live app** | CH1 + CH2 from the same USB block, phase delay |
| **Software calibration** | Non-destructive gain/offset, stored in JSON |
| **Export** | CSV + MAT + PNG report per capture |
| **Simulator mode** | Works without hardware for testing |

---

## Requirements

- macOS 12 or later
- [Miniconda](https://docs.conda.io/en/latest/miniconda.html) or Anaconda
- MATLAB R2022a or later with the Python interface enabled
- Hantek 6022BE oscilloscope (for USB modes)

---

## Quick install

```bash
git clone https://github.com/efloresaraya/Hantek-for-Matlab-6022BE.git
cd Hantek-for-Matlab-6022BE
bash install.sh
```

The script creates the conda environment, verifies libusb, and prints the
one-time MATLAB command needed to link Python.

---

## Manual install

```bash
conda env create -f environment.yml
conda activate hantek6022be-matlab
```

Find the Python path:

```bash
which python          # copy this path
```

In MATLAB (run once):

```matlab
pyenv("Version", "/path/to/your/conda/envs/hantek6022be-matlab/bin/python")
```

Verify:

```matlab
pyenv
```

---

## Usage

### Live single-channel app (CH1 or CH2)

```matlab
cd /path/to/Hantek-for-Matlab-6022BE
run("matlab/main_v6_usb_live_app.m")
```

Controls: channel, scale, sample rate, trigger (On / Rise / Fall / Level / Pos%),
time window, vertical range, software calibration, save.

### Live dual-channel app (CH1 + CH2)

```matlab
run("matlab/main_v9_usb_dual_live_app.m")
```

Shows both channels from the same USB acquisition block. Includes phase delay,
per-channel FFT and metrics table, presets, and dual CSV/MAT/PNG export.

### Calibration check (non-destructive)

Connect a channel to the built-in calibrator (1 kHz square wave), then:

```matlab
run("matlab/main_v8_calibration_check.m")    % CH1
calibrationChannel = 2;
run("matlab/main_v8_calibration_check.m")    % CH2
```

Measures actual levels, computes gain/offset correction and saves them to
`data/software_calibration.json`. Nothing is written to the oscilloscope EEPROM.

Enable calibration in any acquisition:

```matlab
data = hantek_acquire("usb", ...
    "channel", 1, ...
    "sampleRate", 1e6, ...
    "nSamples", 20000, ...
    "voltsPerDiv", 1.0, ...
    "applyCalibration", true);
```

### Acquire from Python

```bash
conda activate hantek6022be-matlab
python python/capture_example.py --mode usb --output data/raw/capture.csv
python python/test_connection.py --mode usb
```

### Simulator (no hardware needed)

```matlab
data = hantek_acquire("simulator");
```

```bash
python python/capture_example.py --mode simulator --output data/examples/sim.csv
```

---

## Project structure

```
matlab/
  hantek_acquire.m           single-channel acquisition (USB / CSV / simulator)
  hantek_acquire_dual.m      simultaneous CH1+CH2 from one USB block
  hantek_live_app.m          single-channel live GUI
  hantek_dual_live_app.m     dual-channel live GUI
  analyze_signal.m           Vpp, RMS, frequency, jitter, duty cycle
  analyze_dual_signal.m      per-channel metrics + inter-channel delay and phase
  compute_fft.m              Hanning-windowed FFT with calibrated magnitude
  save_capture_bundle.m      export MAT + CSV + PNG (single)
  save_dual_capture_bundle.m export MAT + CSV + PNG (dual, with raw overlay)
  main_v6_usb_live_app.m     entry point — single-channel live
  main_v7_ch2_diagnostic.m   dual diagnostic script
  main_v8_calibration_check.m non-destructive calibration measurement
  main_v9_usb_dual_live_app.m entry point — dual-channel live

python/
  hantek_usb_backend.py      direct USB backend (firmware, bulk transfer, demux)
  hantek_adapter.py          mode selector (usb / csv / simulator / openhantek)
  software_calibration.py    load and apply JSON calibration coefficients
  diagnostic_logger.py       timestamped session log
  signal_utils.py            CSV I/O, FFT, capture dict helpers
  hantek_simulator.py        synthetic signal generator

data/
  software_calibration.json  local gain/offset coefficients (not EEPROM)
  raw/                       raw CSV captures (git-ignored)
  processed/                 reports and exports (git-ignored)
  logs/                      diagnostic logs (git-ignored)
```

---

## How the USB backend works

1. Detects the oscilloscope at VID/PID `04B4:6022` (loader) or `04B5:6022` (active).
2. If in loader state, uploads the firmware via Intel HEX + control transfers
   (SHA256-verified before upload).
3. Configures gain, sample rate and channel count via vendor control requests.
4. Reads raw bytes via bulk endpoint `0x86`.
5. Demuxes interleaved bytes, applies oversampling average, and converts to volts.

The firmware file from the bundled OpenHantek source is used read-only — OpenHantek
is never compiled or executed.

---

## macOS USB permissions

On macOS, libusb can access USB devices without `sudo`. If you get permission
errors, check that no other USB driver has claimed the device:

```bash
system_profiler SPUSBDataType | grep -A5 "Hantek"
```

---

## License

MIT — see [LICENSE](LICENSE) if present, otherwise use freely with attribution.
