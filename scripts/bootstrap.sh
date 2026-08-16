#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SGLANG_PIN="${H3_SGLANG_PIN:-d3589a7251e4df6710e14ac55071585e80ae62c7}"
SGLANG_SOURCE="${H3_SGLANG_SOURCE:-https://github.com/sgl-project/sglang.git}"
SGLANG_DIR="${H3_SGLANG_DIR:-$ROOT/.third_party/sglang}"
VENV_DIR="${H3_VENV:-$ROOT/.venv}"
PATCH="$ROOT/patches/sglang/0001-allow-minimax-h3-480p-targets.patch"

check_patch() {
  if git apply --reverse --check "$PATCH"; then
    printf 'SGLang 480p patch is already applied.\n'
    return 0
  fi
  if git apply --check "$PATCH"; then
    git apply "$PATCH"
    return 0
  fi
  printf 'SGLang source does not match the pinned 480p patch.\n' >&2
  return 1
}

if [[ ! -d "$VENV_DIR" ]]; then
  python3.12 -m venv "$VENV_DIR"
fi
PYTHON="$VENV_DIR/bin/python"

if [[ ! -d "$SGLANG_DIR/.git" ]]; then
  git clone "$SGLANG_SOURCE" "$SGLANG_DIR"
fi

cd "$SGLANG_DIR"
if git apply --reverse --check "$PATCH"; then
  patched=1
else
  patched=0
fi
if [[ "$patched" == 0 ]] && ! git diff --quiet; then
  printf 'SGLang source has unrelated local changes; refusing to update.\n' >&2
  exit 1
fi

current_head="$(git rev-parse HEAD)"
if [[ "$current_head" != "$SGLANG_PIN" ]]; then
  if [[ "$patched" == 1 ]]; then
    printf 'Patched SGLang source is not at the expected commit; refusing to switch versions.\n' >&2
    exit 1
  fi
  git fetch origin "$SGLANG_PIN"
  git checkout "$SGLANG_PIN"
fi

if [[ "$patched" == 0 ]]; then
  check_patch
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

printf 'SGLang %s is patched and installed in %s.\n' "$SGLANG_PIN" "$VENV_DIR"
