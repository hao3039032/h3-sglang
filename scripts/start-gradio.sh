#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${H3_VENV:-$ROOT/.venv}"
PYTHON="${PYTHON_BIN:-$VENV_DIR/bin/python}"

export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
export H3_SGLANG_BASE_URL="${H3_SGLANG_BASE_URL:-http://127.0.0.1:30010}"
export H3_OUTPUT_DIR="${H3_OUTPUT_DIR:-$ROOT/outputs}"
mkdir -p "$H3_OUTPUT_DIR"
exec "$PYTHON" "$ROOT/app.py"
