#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SGLANG_PIN="${H3_SGLANG_PIN:-d3589a7251e4df6710e14ac55071585e80ae62c7}"
SGLANG_SOURCE="${H3_SGLANG_SOURCE:-https://github.com/sgl-project/sglang.git}"
SGLANG_DIR="${H3_SGLANG_DIR:-$ROOT/.third_party/sglang}"
VENV_DIR="${H3_VENV:-$ROOT/.venv}"
PATCH_DIR="$ROOT/patches/sglang"
PATCHES=("$PATCH_DIR"/*.patch)

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
  all_patches_applied=1
  for patch in "${PATCHES[@]}"; do
    if ! git apply --reverse --check "$patch"; then
      all_patches_applied=0
      break
    fi
  done
  if [[ "$all_patches_applied" != 1 ]]; then
    printf 'SGLang source has unrelated or partially applied changes.\n' >&2
    exit 1
  fi
fi

for patch in "${PATCHES[@]}"; do
  if git apply --reverse --check "$patch"; then
    continue
  fi
  if git apply --check "$patch"; then
    git apply "$patch"
    continue
  fi
  printf 'SGLang source does not match patch: %s\n' "$patch" >&2
  exit 1
done

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

printf 'SGLang %s is patched and installed in %s.\n' "$SGLANG_PIN" "$VENV_DIR"
