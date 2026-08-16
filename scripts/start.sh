#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_PATH="${H3_SGLANG_MODEL_PATH:-}"
SGLANG_PORT="${H3_SGLANG_PORT:-30010}"
STARTUP_TIMEOUT="${H3_STARTUP_TIMEOUT_SECONDS:-3600}"
PYTHON="${PYTHON_BIN:-python3}"

if [[ -z "$MODEL_PATH" ]]; then
  printf 'H3_SGLANG_MODEL_PATH is required; mount the complete MiniMax-H3 model root.\n' >&2
  exit 1
fi
if [[ "${MINIMAX_H3_LICENSE_ACCEPTED:-}" != 1 ]]; then
  printf 'Set MINIMAX_H3_LICENSE_ACCEPTED=1 after reviewing the MiniMax-H3 license.\n' >&2
  exit 1
fi
case "$STARTUP_TIMEOUT" in
  ''|*[!0-9]*) printf 'H3_STARTUP_TIMEOUT_SECONDS must be a positive integer.\n' >&2; exit 1 ;;
esac
[[ "$STARTUP_TIMEOUT" -ge 1 ]] || { printf 'H3_STARTUP_TIMEOUT_SECONDS must be a positive integer.\n' >&2; exit 1; }

export H3_SGLANG_BASE_URL="${H3_SGLANG_BASE_URL:-http://127.0.0.1:$SGLANG_PORT}"
export H3_OUTPUT_DIR="${H3_OUTPUT_DIR:-$ROOT/outputs}"
mkdir -p "$H3_OUTPUT_DIR"

"$ROOT/scripts/serve.sh" &
server_pid=$!
gradio_pid=

terminate() {
  trap - TERM INT HUP
  [[ -z "$gradio_pid" ]] || kill -TERM "$gradio_pid" 2>/dev/null || true
  kill -TERM "$server_pid" 2>/dev/null || true
  [[ -z "$gradio_pid" ]] || wait "$gradio_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap terminate TERM INT HUP

if ! "$PYTHON" - "$H3_SGLANG_BASE_URL" "$STARTUP_TIMEOUT" <<'PY'
import sys
import time
import urllib.error
import urllib.request

url, timeout_seconds = sys.argv[1], int(sys.argv[2])
deadline = time.monotonic() + timeout_seconds
while time.monotonic() < deadline:
    try:
        with urllib.request.urlopen(f"{url.rstrip('/')}/health", timeout=2) as response:
            if 200 <= response.status < 300:
                raise SystemExit(0)
    except (OSError, urllib.error.URLError):
        pass
    time.sleep(1)
raise SystemExit(f"SGLang did not become ready within {timeout_seconds} seconds")
PY
then
  status=$?
  terminate
  exit "$status"
fi

"$ROOT/scripts/start-gradio.sh" &
gradio_pid=$!

set +e
wait -n "$server_pid" "$gradio_pid"
status=$?
set -e
terminate
exit "$status"
