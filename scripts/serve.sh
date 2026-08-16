#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${H3_VENV:-$ROOT/.venv}"
SGLANG="${SGLANG_BIN:-$VENV_DIR/bin/sglang}"
MODEL_PATH="${H3_SGLANG_MODEL_PATH:-}"
MODEL_VARIANT="${H3_MODEL_VARIANT:-ref2va}"
HOST="${H3_SGLANG_HOST:-127.0.0.1}"
PORT="${H3_SGLANG_PORT:-30010}"
TP_SIZE="${H3_TP_SIZE:-2}"
ULYSSES_DEGREE="${H3_ULYSSES_DEGREE:-1}"
PERFORMANCE_MODE="${H3_PERFORMANCE_MODE:-memory}"
DIT_QUANT="${H3_DIT_QUANT:-none}"
RESIDENT_LAYERS="${H3_DIT_RESIDENT_LAYERS:-20}"

if [[ -z "$MODEL_PATH" ]]; then
  printf 'H3_SGLANG_MODEL_PATH is required; this repository does not download weights.\n' >&2
  exit 1
fi
case "$MODEL_PATH" in
  /*) ;;
  *) printf 'H3_SGLANG_MODEL_PATH must be an absolute local model-root directory.\n' >&2; exit 1 ;;
esac
if [[ ! -d "$MODEL_PATH" ]]; then
  printf 'Model root does not exist: %s\n' "$MODEL_PATH" >&2
  exit 1
fi
case "$MODEL_VARIANT" in
  fl2va|ref2va) ;;
  *) printf 'H3_MODEL_VARIANT must be fl2va or ref2va.\n' >&2; exit 1 ;;
esac
case "$TP_SIZE" in
  ''|*[!0-9]*) printf 'H3_TP_SIZE must be a positive integer.\n' >&2; exit 1 ;;
esac
[[ "$TP_SIZE" -ge 1 ]] || { printf 'H3_TP_SIZE must be a positive integer.\n' >&2; exit 1; }
case "$ULYSSES_DEGREE" in
  ''|*[!0-9]*) printf 'H3_ULYSSES_DEGREE must be a positive integer.\n' >&2; exit 1 ;;
esac
[[ "$ULYSSES_DEGREE" -ge 1 ]] || { printf 'H3_ULYSSES_DEGREE must be a positive integer.\n' >&2; exit 1; }
case "$DIT_QUANT" in
  none|fp8) ;;
  *) printf 'H3_DIT_QUANT must be none or fp8.\n' >&2; exit 1 ;;
esac
if [[ ! -x "$SGLANG" ]]; then
  printf 'SGLang executable not found: %s\n' "$SGLANG" >&2
  exit 1
fi

args=(
  serve
  --model-path "$MODEL_PATH"
  --model-variant "$MODEL_VARIANT"
  --tp-size "$TP_SIZE"
  --ulysses-degree "$ULYSSES_DEGREE"
  --performance-mode "$PERFORMANCE_MODE"
  --layerwise-offload-components dit,text_encoder,vae
  --dit-offload-prefetch-size "${H3_DIT_OFFLOAD_PREFETCH_SIZE:-1}"
  --dit-layerwise-resident-layers "$RESIDENT_LAYERS"
  --enable-torch-compile false
  --host "$HOST"
  --port "$PORT"
)
if [[ -n "${H3_NUM_GPUS:-}" ]]; then
  case "$H3_NUM_GPUS" in
    ''|*[!0-9]*) printf 'H3_NUM_GPUS must be a positive integer.\n' >&2; exit 1 ;;
  esac
  [[ "$H3_NUM_GPUS" -ge 1 ]] || { printf 'H3_NUM_GPUS must be a positive integer.\n' >&2; exit 1; }
  args+=(--num-gpus "$H3_NUM_GPUS")
fi
if [[ "$DIT_QUANT" == fp8 ]]; then
  args+=(--quantization fp8)
fi
if [[ -n "${H3_SGLANG_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<<"$H3_SGLANG_EXTRA_ARGS"
  args+=("${extra_args[@]}")
fi

exec "$SGLANG" "${args[@]}"
