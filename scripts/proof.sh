#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flags=()
if bend --help | rg -q -- '--safe'; then
  flags+=(--safe)
fi
if ! verdict="$(bend PROOF.bend "${flags[@]}" "$@")"; then
  printf '%s\n' "$verdict"
  exit 1
fi
printf '%s\n' "$verdict"
# Bend 2.0.32 may exit zero while reporting unsafe dependencies. Require the
# positive verdict as well as successful execution.
rg -q '^ALL PROOFS CHECK$' <<< "$verdict"
