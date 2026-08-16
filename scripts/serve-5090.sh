#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The upstream 2x RTX 5090 recipe is the default. GPU visibility is left to
# the runtime environment; only an explicit H3_NUM_GPUS adds --num-gpus.
export H3_TP_SIZE="${H3_TP_SIZE:-2}"
export H3_ULYSSES_DEGREE="${H3_ULYSSES_DEGREE:-1}"
export H3_PERFORMANCE_MODE="${H3_PERFORMANCE_MODE:-memory}"
export H3_DIT_RESIDENT_LAYERS="${H3_DIT_RESIDENT_LAYERS:-20}"
export SGLANG_ONLINE_QUANT_CHECKPOINT_DEVICE="${SGLANG_ONLINE_QUANT_CHECKPOINT_DEVICE:-cpu}"
export SGLANG_ONLINE_QUANT_STREAM_POSTPROCESS="${SGLANG_ONLINE_QUANT_STREAM_POSTPROCESS:-1}"
export SGLANG_USE_RUNAI_MODEL_STREAMER="${SGLANG_USE_RUNAI_MODEL_STREAMER:-0}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
export H3_PIN_CPU_MEMORY="${H3_PIN_CPU_MEMORY:-false}"

exec "$ROOT/scripts/serve.sh"
