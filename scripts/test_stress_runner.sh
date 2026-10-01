#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
mkdir -p build
rm -f build/stress-tool-tests
bend src/stress_tool.bend -o build/stress-tool-tests
temporary=$(mktemp -d "${TMPDIR:-/tmp}/bend-stress-contracts.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
fixture_root="$temporary/root with spaces"
mkdir -p "$fixture_root"/{src,scripts,build} "$temporary/bin"
printf 'frozen source\n' > "$fixture_root/src/frozen.bend"
printf 'frozen script\n' > "$fixture_root/scripts/fixture.sh"
cp tests/fixtures/stress/worker.sh "$fixture_root/build/voxel-demo"
binary="$fixture_root/"'worker ; $(touch injected).sh'
cp tests/fixtures/stress/worker.sh "$binary"
export STRESS_TOOL="$root/build/stress-tool-tests" STRESS_TRACE="$temporary/trace"
export BENCH_TOOL="$STRESS_TOOL" BENCH_VERSION=2.0.34 CUDA_HOME=inherited
cp tests/fixtures/benchmark/git.sh "$temporary/bin/git"
cp tests/fixtures/benchmark/date.sh "$temporary/bin/date"
cat > "$temporary/bin/bend" <<'BEND'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 = version ]]; then printf 'bend %s\n' "$BENCH_VERSION"; exit 0; fi
test "${CUDA_HOME-unset}" = unset
case ${STRESS_COMPILE_FAIL:-0} in 1) exit 1;; 2) exit 0;; esac
cp "$STRESS_TOOL" "$3"
chmod +x "$3"
BEND
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
tool() { "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" "$@"; }
fail() {
  local expected=$1 actual=0
  shift
  "$@" > "$temporary/fail.stdout" 2> "$temporary/fail.stderr" || actual=$?
  test "$actual" = "$expected" || { cat "$temporary/fail.stderr" >&2; exit 1; }
}
field() { grep -Fq -- "$2" "$1"; }
count() { test "$(grep -cE -- "$2" "$1")" = "$3"; }
: > "$STRESS_TRACE"
tool --cases atelier atelier-night atelier-camera atelier-aim atelier-carve --warmup 2 --frames 24 --edit-every 4 --output 'pilot with spaces' --binary "$binary" > "$temporary/pilot.stdout"
report="$fixture_root/pilot with spaces/report.json"
count "$report" '"pass": true' 6
count "$report" '"errors": \[\]' 5
count "$report" '"measured_frames": 24' 6
count "$report" '"edits": 6' 1
count "$report" '"shadow_refreshes": 7' 1
count "$report" '"present_mode": "immediate"' 5
field "$report" '"solid_cells_end": 803850'
field "$report" '"throughput_fps": 1000.0'
field "$report" '"warmup_frames": 2'
field "$report" '"edit_every_frames": 4'
field "$report" '"body_budget": 2048'
field "$report" '"working_tree_dirty": true'
field "$report" '"git_revision": "0123456789abcdef0123456789abcdef01234567"'
field "$report" '"bend": "bend 2.0.34"'
field "$report" '"binary_sha256": '"\"$(sha256sum "$binary" | cut -d ' ' -f 1)\""
field "$report" '"src/frozen.bend": '"\"$(sha256sum "$fixture_root/src/frozen.bend" | cut -d ' ' -f 1)\""
field "$report" '"scripts/fixture.sh": '"\"$(sha256sum "$fixture_root/scripts/fixture.sh" | cut -d ' ' -f 1)\""
field "$report" 'both binaries use the current native library and shaders'
test ! -e "$fixture_root/injected"
for name in atelier atelier-night atelier-camera atelier-aim atelier-carve; do
  test -s "$fixture_root/pilot with spaces/$name.csv"
  field "$fixture_root/pilot with spaces/$name.stderr" 'fixture stderr é'
done
cut -f 2- "$STRESS_TRACE" > "$temporary/trace.fields"
cat > "$temporary/expected.trace" <<'TRACE'
0	2	24	0	2048	640x360	inherited
6	2	24	0	2048	640x360	inherited
1	2	24	0	2048	640x360	inherited
2	2	24	0	2048	640x360	inherited
3	2	24	4	2048	640x360	inherited
TRACE
cmp "$temporary/expected.trace" "$temporary/trace.fields"
grep '^Stress ' "$temporary/pilot.stdout" > "$temporary/messages"
cat > "$temporary/expected.messages" <<'MESSAGES'
Stress atelier: static workload, 640x360
Stress atelier-night: night workload, 640x360
Stress atelier-camera: camera workload, 640x360
Stress atelier-aim: aim workload, 640x360
Stress atelier-carve: carve workload, 640x360
MESSAGES
cmp "$temporary/expected.messages" "$temporary/messages"
count "$temporary/pilot.stdout" '"throughput_fps": 1000.0' 5
: > "$STRESS_TRACE"
tool --output defaults > "$temporary/defaults.stdout"
report="$fixture_root/defaults/report.json"
count "$report" '"pass": true' 6
count "$report" '"measured_frames": 180' 6
count "$report" '"edits": 6' 1
cut -f 2- "$STRESS_TRACE" > "$temporary/trace.fields"
cat > "$temporary/expected.trace" <<'TRACE'
0	30	180	0	2048	640x360	inherited
6	30	180	0	2048	640x360	inherited
1	30	180	0	2048	640x360	inherited
2	30	180	0	2048	640x360	inherited
3	30	180	30	2048	640x360	inherited
TRACE
cmp "$temporary/expected.trace" "$temporary/trace.fields"
tool --ca atelier --war=+0 --fr=1 --edit=0 --body=+1 --time=1_80 --res=1920x1080 --out custom > "$temporary/custom.stdout"
report="$fixture_root/custom/report.json"
field "$report" '"warmup_frames": 0'
field "$report" '"body_budget": 1'
field "$report" '"measured_frames": 1'
field "$temporary/custom.stdout" '1920x1080'
env STRESS_PRESENT=repeat "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --frames 1 --warmup 0 --output repeated > "$temporary/repeated.stdout"
field "$fixture_root/repeated/report.json" '"present_mode": "mailbox"'
for presentation in missing mixed fifo; do
  fail 1 env STRESS_PRESENT="$presentation" "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output "bad-$presentation"
  field "$fixture_root/bad-$presentation/report.json" 'Unpaced present mode was not confirmed'
  count "$fixture_root/bad-$presentation/report.json" '"pass": false' 2
done
field "$fixture_root/bad-mixed/report.json" '"present_mode": "immediate"'
fail 1 env STRESS_EXIT=7 "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier atelier-night --warmup 0 --frames 1 --output failed-process
count "$fixture_root/failed-process/report.json" '"pass": false' 3
field "$fixture_root/failed-process/report.json" 'Process exited 7'
test -s "$fixture_root/failed-process/atelier-night.csv"
fail 1 env STRESS_SLOW=1 STRESS_PID_FILE="$temporary/slow.pid" "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --timeout 1 --output timeout
field "$fixture_root/timeout/report.json" 'Process exited 124'
field "$fixture_root/timeout/atelier.csv" 'world,803970,6,2034,2048'
field "$fixture_root/timeout/atelier.stderr" 'fixture stderr é'
test -s "$temporary/slow.pid"
! kill -0 "$(cat "$temporary/slow.pid")" 2>/dev/null
fail 1 env STRESS_SLOW=1 STRESS_IGNORE_TERM=1 STRESS_PID_FILE="$temporary/forced.pid" "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --timeout 1 --output forced-timeout
field "$fixture_root/forced-timeout/report.json" 'Process exited 124'
field "$fixture_root/forced-timeout/atelier.csv" 'world,803970,6,2034,2048'
field "$fixture_root/forced-timeout/atelier.stderr" 'fixture stderr é'
test -s "$temporary/forced.pid"
! kill -0 "$(cat "$temporary/forced.pid")" 2>/dev/null
fail 1 env STRESS_SIGNAL=TERM "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output self-term
field "$fixture_root/self-term/report.json" 'Process exited 143'
fail 1 env STRESS_EXIT=143 "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output explicit-143
field "$fixture_root/explicit-143/report.json" 'Process exited 143'
fail 1 env STRESS_EXIT=137 "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output explicit-137
field "$fixture_root/explicit-137/report.json" 'Process exited 137'
fail 1 env STRESS_EXIT=137 STRESS_PRESENT=$'immediate\ntimeout: sending signal TERM to command worker' "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output spoofed-deadline
field "$fixture_root/spoofed-deadline/report.json" 'Process exited 137'
env LC_ALL=C STRESS_LOCALE_FILE="$temporary/locale" "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output locale-set > "$temporary/locale.stdout"
test "$(cat "$temporary/locale")" = C
env -u LC_ALL STRESS_LOCALE_FILE="$temporary/locale" "$STRESS_TOOL" --threads 1 --gpu off -- "$fixture_root" --cases atelier --warmup 0 --frames 1 --output locale-unset > "$temporary/locale.stdout"
test "$(cat "$temporary/locale")" = unset
fail 2 tool --warmup -1
fail 2 tool --frames 0
fail 2 tool --frames '"2"'
fail 2 tool --edit-every -1
fail 2 tool --timeout 0
fail 2 tool --timeout 4294965
fail 2 tool --body-budget 0
fail 2 tool --body-budget 65537
fail 2 tool --cases atelier-camera --frames 3
fail 2 tool --warmup 5000 --frames 1
fail 2 tool --cases
fail 2 tool --cases unknown
fail 2 tool --resolution 1920X1080
fail 2 tool --resolution 1920x1080x1
fail 2 tool --resolution +640x360
fail 2 tool --resolution 1920x1080extra
fail 2 tool --resolution 639x360
fail 2 tool --resolution 640x359
fail 2 tool --resolution 7681x360
fail 2 tool --resolution 640x4321
fail 2 tool --resolution 7680x4320
fail 2 tool --binary missing
fail 2 tool --nonsense
fail 2 tool --b 1
fail 2 tool --frames
scripts/benchmark_stress.sh --help > "$temporary/shim-help"
ln -s "$root/scripts/benchmark_stress.sh" "$temporary/stress-link"
"$temporary/stress-link" --help > "$temporary/link-help"
cmp "$temporary/shim-help" "$temporary/link-help"
field "$temporary/shim-help" 'Measure the Light Atelier stress workloads.'
fail 1 env STRESS_COMPILE_FAIL=1 scripts/benchmark_stress.sh --help
fail 1 env STRESS_COMPILE_FAIL=2 scripts/benchmark_stress.sh --help
printf 'Stress runner CLI, metadata, retained logs and failure contracts passed\n'
