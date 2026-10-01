#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
bash scripts/proof.sh
rm -f build/megascene-admission-generator
bend src/megascene_admit.bend -o build/megascene-admission-generator
for suite in world input-aim probe resolution mesh face-audit color invariants megascene-admission megascene-operational; do
  rm -f "build/$suite-tests"
  bend "tests/$suite.bend" -o "build/$suite-tests"
  "build/$suite-tests"
done
g++ -O2 -std=c++17 -Wall -Wextra -Wno-missing-field-initializers \
  tests/native_geometry.cpp -lvulkan -lX11 -lcrypto -o build/native-geometry-tests
build/native-geometry-tests
bash scripts/test_schedule_contracts.sh
bash scripts/test_benchmark_contracts.sh
bash scripts/test_stress_parser.sh
bash scripts/test_stress_runner.sh
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/megascene_schedule_parity.py
