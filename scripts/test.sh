#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for suite in world input-aim probe; do
  bend "tests/$suite.bend" -o "build/$suite-tests"
  "build/$suite-tests"
done
python3 -m unittest discover -s tests -p 'test_*.py'
