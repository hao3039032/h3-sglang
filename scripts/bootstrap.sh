#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SGLANG_PIN="${H3_SGLANG_PIN:-480a8ba7cae46658380428576b51d682f28489f1}"
SGLANG_SOURCE="${H3_SGLANG_SOURCE:-https://github.com/hao3039032/sglang-h3.git}"
SGLANG_DIR="${H3_SGLANG_DIR:-$ROOT/.third_party/sglang}"
VENV_DIR="${H3_VENV:-$ROOT/.venv}"

if [[ ! -d "$VENV_DIR" ]]; then
  python3.12 -m venv "$VENV_DIR"
fi
PYTHON="$VENV_DIR/bin/python"

if [[ ! -d "$SGLANG_DIR/.git" ]]; then
  git clone "$SGLANG_SOURCE" "$SGLANG_DIR"
fi

cd "$SGLANG_DIR"
current_head="$(git rev-parse HEAD)"
source_is_clean=0
if git diff --quiet && git diff --cached --quiet; then
  source_is_clean=1
fi

if [[ "$current_head" != "$SGLANG_PIN" ]]; then
  if [[ "$source_is_clean" != 1 ]]; then
    printf 'SGLang source HEAD %s is not pinned and has local changes.\n' \
      "$current_head" >&2
    exit 1
  fi
  git fetch origin "$SGLANG_PIN"
  git checkout "$SGLANG_PIN"
elif [[ "$source_is_clean" != 1 ]]; then
  printf 'SGLang fork source has unrelated local changes.\n' >&2
  exit 1
fi

if [[ "${H3_SKIP_APP_INSTALL:-0}" != "1" ]]; then
  if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$PYTHON" -e "$ROOT"
  else
    "$PYTHON" -m pip install -e "$ROOT"
  fi
fi

if [[ "${H3_SKIP_SGLANG_INSTALL:-0}" != "1" ]]; then
  if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$PYTHON" --prerelease=allow \
      -e "$SGLANG_DIR/python[diffusion]"
  else
    "$PYTHON" -m pip install -e "$SGLANG_DIR/python[diffusion]"
  fi
fi

# FlashInfer JIT invokes ninja by name. A system-site venv can expose the
# Python package while its executable remains outside PATH; serve.sh discovers
# that directory dynamically.
if ! "$PYTHON" -c 'import ninja' >/dev/null 2>&1; then
  "$PYTHON" -m pip install 'ninja>=1.11,<2'
fi

printf 'SGLang fork %s is installed in %s.\n' "$SGLANG_PIN" "$VENV_DIR"
