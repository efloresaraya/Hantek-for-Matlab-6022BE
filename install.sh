#!/usr/bin/env bash
# install.sh — set up the Hantek 6022BE MATLAB Toolkit on macOS
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="hantek6022be-matlab"
PYTHON_VERSION="3.11"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Hantek 6022BE MATLAB Toolkit — Installer  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Check conda ──────────────────────────────────────────────────────────
if ! command -v conda &>/dev/null; then
    echo "❌  conda not found."
    echo "    Install Miniconda from https://docs.conda.io/en/latest/miniconda.html"
    echo "    then run this script again."
    exit 1
fi
echo "✅  conda: $(conda --version)"

# ── 2. Create or update the conda environment ───────────────────────────────
if conda env list | grep -q "^${ENV_NAME}"; then
    echo "✅  conda env '${ENV_NAME}' already exists — updating..."
    conda env update -f "${REPO_DIR}/environment.yml" --prune -q
else
    echo "📦  Creating conda env '${ENV_NAME}' (Python ${PYTHON_VERSION})..."
    conda env create -f "${REPO_DIR}/environment.yml" -q
fi

# ── 3. Resolve python path inside the env ───────────────────────────────────
PYTHON_BIN="$(conda run -n "${ENV_NAME}" which python)"
echo "✅  Python: ${PYTHON_BIN}"

# ── 4. Check libusb (required for PyUSB on macOS) ───────────────────────────
if conda run -n "${ENV_NAME}" python -c "import usb.core; usb.core.find()" &>/dev/null 2>&1; then
    echo "✅  PyUSB + libusb: OK"
else
    echo "⚠️   PyUSB could not find libusb."
    if command -v brew &>/dev/null; then
        echo "    Installing libusb via Homebrew..."
        brew install libusb
    else
        echo "    Install libusb manually:"
        echo "      brew install libusb"
        echo "    or via conda-forge (already in environment.yml)."
    fi
fi

# ── 5. Verify firmware file ──────────────────────────────────────────────────
FIRMWARE="${REPO_DIR}/OpenHantek6022/OpenHantek6022-main/openhantek/res/firmware/dso6022be-firmware.hex"
EXPECTED_SHA="7773d886de861e2a95b159f103135b06391a6433adf0727d3d1e23aec9e65cfd"

if [[ -f "${FIRMWARE}" ]]; then
    ACTUAL_SHA="$(shasum -a 256 "${FIRMWARE}" | awk '{print $1}')"
    if [[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]]; then
        echo "✅  Firmware SHA256: OK"
    else
        echo "⚠️   Firmware SHA256 mismatch. Re-clone the repository."
    fi
else
    echo "⚠️   Firmware file not found at expected path:"
    echo "    ${FIRMWARE}"
    echo "    The USB backend requires this file. Make sure you cloned the full repo."
fi

# ── 6. Quick Python smoke test ───────────────────────────────────────────────
echo ""
echo "Running simulator smoke test..."
if conda run -n "${ENV_NAME}" python -c "
import sys
sys.path.insert(0, '${REPO_DIR}/python')
from hantek_simulator import acquire
d = acquire(sample_rate=1e6, n_samples=1000)
assert len(d['voltage']) == 1000
print('  simulator: OK')
"; then
    echo "✅  Python smoke test passed"
else
    echo "❌  Python smoke test failed — check the environment"
    exit 1
fi

# ── 7. Print MATLAB setup instructions ──────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   One-time MATLAB setup (run this once)     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  In MATLAB, run:"
echo ""
echo "    pyenv(\"Version\", \"${PYTHON_BIN}\")"
echo ""
echo "  Then verify:"
echo ""
echo "    pyenv"
echo ""
echo "  To test without hardware:"
echo ""
echo "    cd ${REPO_DIR}"
echo "    data = hantek_acquire(\"simulator\");"
echo ""
echo "  To start the live app:"
echo ""
echo "    run(\"${REPO_DIR}/matlab/main_v6_usb_live_app.m\")"
echo ""
echo "Done. 🎉"
