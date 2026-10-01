#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
fixtures=$root/tests/fixtures/benchmark
mkdir -p build
rm -f build/benchmark-{tool,metrics}-tests
bend src/benchmark_tool.bend -o build/benchmark-tool-tests
bend tests/benchmark-metrics.bend -o build/benchmark-metrics-tests
build/benchmark-metrics-tests --threads 1 -- "$fixtures"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/bend-benchmark-contracts.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
export BENCH_ROOT=$temporary BENCH_STATE=$temporary/state BENCH_FIXTURES=$fixtures
export BENCH_TOOL=$root/build/benchmark-tool-tests CUDA_HOME=inherited
mkdir -p "$temporary"/{src,scripts,bin,state,build}
printf 'frozen source\n' > "$temporary/src/face_profile.bend"
printf 'frozen script\n' > "$temporary/scripts/fixture.txt"
for name in bend git date; do ln -s "$fixtures/$name.sh" "$temporary/bin/$name"; done
for name in baseline candidate; do cp "$fixtures/worker.sh" "$temporary/$name"; done
export PATH=$temporary/bin:$PATH
reset_workers() { truncate -s 0 "$BENCH_STATE"/{baseline,candidate,trace}; }
tool() { "$BENCH_TOOL" --threads 1 --gpu off -- "$temporary" "$@"; }
fail() {
  local expected=$1 actual=0
  shift
  "$@" > "$temporary/fail.stdout" 2> "$temporary/fail.stderr" || actual=$?
  test "$actual" = "$expected" || { cat "$temporary/fail.stderr" >&2; exit 1; }
}
fail 1 "$root/build/benchmark-metrics-tests" --threads 1 -- --schedule-overflow
grep -q 'nonfinite schedule numeric result' "$temporary/fail.stderr"
fail 1 "$root/build/benchmark-metrics-tests" --threads 1 -- --schedule-infinity
grep -q 'nonfinite schedule numeric literal' "$temporary/fail.stderr"
for runs in 2 3; do
  reset_workers
  tool parallel "$temporary/baseline" "$temporary/candidate" --runs "$runs" --threads 1 6 12 --output "$temporary/parallel-$runs" > "$temporary/stdout"
  cmp "$fixtures/parallel-$runs.stdout" "$temporary/stdout"
  sed "s|$temporary|@ROOT@|g" "$temporary/parallel-$runs/report.json" | sha256sum | cut -d ' ' -f 1 > "$temporary/hash"
  cmp "$fixtures/parallel-$runs.sha256" "$temporary/hash"
  sed "s|$temporary|@ROOT@|g" "$BENCH_STATE/trace" | cmp "$fixtures/parallel-$runs.trace" -
  for name in baseline candidate; do
    cmp "$fixtures/ordinary.csv" <(tail -n +2 "$temporary/parallel-$runs/t1-$name-0.csv")
    test "$(cat "$temporary/parallel-$runs/t1-$name-0.stderr")" = 'fixture stderr'
  done
done
reset_workers
tool faces --output ./face-out//./ > "$temporary/stdout"
cmp "$fixtures/faces.json" "$temporary/face-out/report.json"
sed "s|$temporary|@ROOT@|g" "$temporary/stdout" | cmp "$fixtures/faces.stdout" -
sed "s|$temporary|@ROOT@|g" "$BENCH_STATE/trace" | cmp "$fixtures/faces.trace" -
mkdir "$temporary/wide"
cp "$fixtures/worker.sh" "$temporary/wide/worker.sh"
sed 's/,2,12,30,6,4,2,8,9$/,2,12,30,4294967295,4294967295,2,8,9/' "$fixtures/ordinary.csv" > "$temporary/wide/ordinary.csv"
env BENCH_FIXTURES="$temporary/wide" "$BENCH_TOOL" --threads 1 -- "$temporary" faces --output wide-counts > "$temporary/stdout"
test "$(grep -c '"face_checks_total": 8589934590' "$temporary/wide-counts/report.json")" = 3
for mode in faces parallel; do
  tool "$mode" --help > "$temporary/help"
  fail 2 tool "$mode" --timeout 0
  fail 2 tool "$mode" --timeout 4294968
  fail 2 tool "$mode" --nonsense
done
fail 2 tool parallel "$temporary/baseline" "$temporary/candidate" --runs 1
fail 2 tool parallel "$temporary/baseline" "$temporary/candidate" --runs '"2"'
fail 2 tool parallel "$temporary/baseline" "$temporary/candidate" --threads 0
fail 2 tool parallel "$temporary/baseline" "$temporary/candidate" --threads
fail 2 tool parallel "$temporary/baseline" "$temporary/candidate" --t 1
reset_workers
tool parallel "$temporary/baseline" "$temporary/candidate" --ru=+2 --thr 1 --time=1_80 --out="$temporary/spellings" > "$temporary/stdout"
test -f "$temporary/spellings/report.json"
reset_workers
tool parallel "$temporary/baseline" "$temporary/candidate" --runs 2 --threads 1 1 --output "$temporary/duplicates" > "$temporary/stdout"
test "$(wc -l < "$temporary/stdout")" = 2
test "$(grep -c '^    "1": {' "$temporary/duplicates/report.json")" = 1
reset_workers
fail 1 env BENCH_EXIT=7 "$BENCH_TOOL" --threads 1 -- "$temporary" parallel "$temporary/baseline" "$temporary/candidate" --runs 2 --threads 1 --output "$temporary/nonzero"
test -s "$temporary/nonzero/t1-baseline-warmup.csv"
test -s "$temporary/nonzero/t1-baseline-warmup.stderr"
test ! -e "$temporary/nonzero/report.json"
mkdir "$temporary/bad"
sed 's/,8,9$/,8,10/' "$fixtures/ordinary.csv" > "$temporary/bad/ordinary.csv"
sed '2i BENCH_FIXTURES="$BENCH_BAD"' "$fixtures/worker.sh" > "$temporary/candidate"
chmod +x "$temporary/candidate"
reset_workers
fail 1 env BENCH_BAD="$temporary/bad" "$BENCH_TOOL" --threads 1 -- "$temporary" parallel "$temporary/baseline" "$temporary/candidate" --runs 2 --threads 1 --output "$temporary/mismatch"
test -s "$temporary/mismatch/t1-candidate-warmup.csv"
test ! -e "$temporary/mismatch/report.json"
printf '#!/bin/sh\nprintf "init,-1\\n"\ncat "$BENCH_FIXTURES/ordinary.csv"\n' > "$temporary/invalid-init"
chmod +x "$temporary/invalid-init"
fail 1 tool parallel "$temporary/invalid-init" "$temporary/baseline" --runs 2 --threads 1 --output "$temporary/invalid-init-output"
test -s "$temporary/invalid-init-output/t1-baseline-warmup.csv"
test ! -e "$temporary/invalid-init-output/report.json"
printf '#!/bin/sh\nsleep 5\n' > "$temporary/slow"
chmod +x "$temporary/slow"
fail 1 tool parallel "$temporary/slow" "$temporary/baseline" --runs 2 --threads 1 --timeout 1 --output "$temporary/timeout"
test ! -e "$temporary/timeout/t1-baseline-warmup.csv"
test ! -e "$temporary/timeout/report.json"
printf '#!/bin/sh\nprintf "init,0\\n"\ncat "$BENCH_FIXTURES/ordinary.csv"\nprintf "é🎉\\n" >&2\n' > "$temporary/unicode"
chmod +x "$temporary/unicode"
tool parallel "$temporary/unicode" "$temporary/unicode" --runs 2 --threads 1 --output "$temporary/unicode-output" > "$temporary/stdout"
printf 'é🎉\n' | cmp "$temporary/unicode-output/t1-baseline-0.stderr" -
printf '#!/bin/sh\nprintf "init,0\\r\\n"\nsed "s/$/\\r/" "$BENCH_FIXTURES/ordinary.csv"\nprintf "crlf\\r\\n" >&2\n' > "$temporary/crlf"
chmod +x "$temporary/crlf"
tool parallel "$temporary/crlf" "$temporary/crlf" --runs 2 --threads 1 --output "$temporary/crlf-output" > "$temporary/stdout"
printf 'crlf\n' | cmp "$temporary/crlf-output/t1-baseline-0.stderr" -
cmp "$fixtures/ordinary.csv" <(tail -n +2 "$temporary/crlf-output/t1-baseline-0.csv")
fail 2 env BENCH_VERSION=2.0.33 "$BENCH_TOOL" --threads 1 -- "$temporary" faces --output wrong-version
fail 1 env BENCH_FAIL_COMPILE=1 "$BENCH_TOOL" --threads 1 -- "$temporary" faces --output failed-compile
test ! -e "$temporary/failed-compile/report.json"
fail 1 env BENCH_FAIL_COMPILE=2 "$BENCH_TOOL" --threads 1 -- "$temporary" faces --output stale-compile
test ! -e "$temporary/build/atelier-face-profile"
test ! -e "$temporary/stale-compile/report.json"
scripts/benchmark_faces.sh --help > "$temporary/shim-help"
ln -s "$root/scripts/benchmark_faces.sh" "$temporary/faces-link"
"$temporary/faces-link" --help > "$temporary/link-help"
cmp "$temporary/shim-help" "$temporary/link-help"
fail 1 env BENCH_FAIL_COMPILE=2 scripts/benchmark_parallel.sh --help
printf 'Benchmark CLI, frozen bytes, numeric semantics and failure contracts passed\n'
