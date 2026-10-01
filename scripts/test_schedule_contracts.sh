#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
fixture=$(mktemp -d "${TMPDIR:-/tmp}/bend-schedule-contracts.XXXXXXXX")
trap 'rm -rf "$fixture"' EXIT
g++ -O2 -std=c++17 tests/native_schedule_points.cpp -lcrypto -o build/native-schedule-points-tests
g++ -O2 -std=c++17 tests/native_schedule_policy.cpp -o build/native-schedule-policy-tests
rm -f build/{schedule-binary,schedule-points,megascene-inputs,megascene-admission-inputs,megascene-schedule}-generator
bend src/schedule_binary.bend -o build/schedule-binary-generator
bend src/schedule_points.bend -o build/schedule-points-generator
bend src/megascene_inputs.bend -o build/megascene-inputs-generator
bend src/megascene_admission_inputs.bend -o build/megascene-admission-inputs-generator
bend src/megascene_schedule.bend -o build/megascene-schedule-generator
for suite in schedule-points schedule-binary megascene-inputs schedule-json; do
  rm -f "build/$suite-tests"
  bend "tests/$suite.bend" -o "build/$suite-tests"
  "build/$suite-tests" --threads 1 -- "$fixture"
done
