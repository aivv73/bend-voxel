#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(bend version 2>/dev/null)" != 'bend 2.0.25' ]]; then
  echo 'This demo is pinned to Bend 2.0.25. Use that compiler; do not update automatically.' >&2
  exit 1
fi
export CUDA_HOME="${CUDA_HOME:-/opt/cuda}"
mkdir -p build
target="${1:-demo}"
case "$target" in demo|snapshot) ;; *) echo "Unknown target: $target" >&2; exit 1;; esac
bend "src/$target.bend" -o "build/voxel-$target"
[[ -f build/voxel-$target.gpu ]] || { echo 'CUDA module missing; check CUDA_HOME.' >&2; exit 1; }
