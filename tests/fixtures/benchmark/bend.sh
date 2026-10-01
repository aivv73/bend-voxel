#!/bin/sh
set -eu
if [ "$1" = version ]; then
  printf 'bend %s\n' "${BENCH_VERSION-2.0.34}"
  exit 0
fi
test "${CUDA_HOME-unset}" = unset
if [ "${BENCH_FAIL_COMPILE-0}" = 1 ]; then exit 1; fi
if [ "${BENCH_FAIL_COMPILE-0}" = 2 ]; then exit 0; fi
case "$1" in
  *benchmark_tool.bend) cp "$BENCH_TOOL" "$3";;
  *) test "$PWD" = "$BENCH_ROOT"; cp "$BENCH_FIXTURES/worker.sh" "$3";;
esac
chmod +x "$3"
