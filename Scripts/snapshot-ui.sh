#!/bin/sh
set -eu

output="${1:-/tmp/lys-workbench.png}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(dirname -- "$script_dir")"

"$script_dir/test-local.sh" >/dev/null
"$project_root/.build/arm64-apple-macosx/debug/LysSnapshot" "$output"
