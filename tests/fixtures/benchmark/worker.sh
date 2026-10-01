#!/bin/sh
# Fixed recorded payloads; this fixture performs no metric calculations.
set -eu
name=$(basename "$0")
printf '%s %s %s %s\n' "$name" "$*" "$PWD" "${CUDA_HOME-unset}" >> "$BENCH_STATE/trace"
if [ "$#" = 0 ]; then
  cat "$BENCH_FIXTURES/ordinary.csv"
else
  count=$(wc -l < "$BENCH_STATE/$name")
  printf '.\n' >> "$BENCH_STATE/$name"
  printf 'init,18014398509481985\n'
  case "$count" in
    0|1) cat "$BENCH_FIXTURES/ordinary.csv";;
    2) cat "$BENCH_FIXTURES/rounding.csv";;
    *) cat "$BENCH_FIXTURES/varying.csv";;
  esac
fi
printf 'fixture stderr\n' >&2
exit "${BENCH_EXIT-0}"
