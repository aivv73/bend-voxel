#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/bend-stress.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
env -u CUDA_HOME bend "$root/src/stress_tool.bend" -o "$temporary/runner"
test -x "$temporary/runner"
"$temporary/runner" --threads 1 --gpu off -- "$root" "$@"
