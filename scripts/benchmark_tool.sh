#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mode=$1
shift
temporary=$(mktemp -d "${TMPDIR:-/tmp}/bend-benchmark.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
env -u CUDA_HOME bend "$root/src/benchmark_tool.bend" -o "$temporary/runner"
test -x "$temporary/runner"
"$temporary/runner" --threads 1 --gpu off -- "$root" "$mode" "$@"
