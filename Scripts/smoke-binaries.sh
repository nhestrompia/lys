#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin_path=$(cd "$root" && swift build --show-bin-path --disable-sandbox)
smoke_root=$(mktemp -d "${TMPDIR:-/private/tmp}/lys-binary-smoke.XXXXXX")
socket="$smoke_root/runtime.sock"
runtime_log="$smoke_root/runtime.log"
runtime_pid=""

cleanup() {
  if [ -n "$runtime_pid" ]; then
    kill "$runtime_pid" 2>/dev/null || true
    wait "$runtime_pid" 2>/dev/null || true
  fi
  rm -f "$socket" "$runtime_log"
  rmdir "$smoke_root" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$bin_path/lysd" --socket "$socket" --workspace "$root" --token smoke-token \
  >"$runtime_log" 2>&1 &
runtime_pid=$!
attempt=0
while [ ! -S "$socket" ] && [ "$attempt" -lt 100 ]; do
  sleep 0.02
  attempt=$((attempt + 1))
done
if [ ! -S "$socket" ]; then
  echo "lysd did not create its authenticated runtime socket" >&2
  exit 1
fi

mcp_response=$(
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"workspace.describe","arguments":{}}}' |
    LYS_RUNTIME_SOCKET="$socket" \
    LYS_TASK_TOKEN="smoke-token" \
    LYS_INTENT_KIND="runTests" \
    "$bin_path/lys-mcp"
)
if ! printf '%s' "$mcp_response" | grep -q '"isError":false'; then
  echo "lys-mcp could not complete an authenticated runtime request" >&2
  exit 1
fi

kill "$runtime_pid"
wait "$runtime_pid" 2>/dev/null || true
runtime_pid=""

set +e
mcp_error=$("$bin_path/lys-mcp" 2>&1)
mcp_status=$?
set -e
if [ "$mcp_status" -ne 64 ] || ! printf '%s' "$mcp_error" | grep -q "LYS_RUNTIME_SOCKET"; then
  echo "lys-mcp did not enforce its runtime authentication environment" >&2
  exit 1
fi

echo "Lys runtime and MCP binary smoke tests passed"
