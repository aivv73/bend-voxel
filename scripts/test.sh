#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for suite in world input-aim probe; do
  bend "tests/$suite.bend" -o "build/$suite-tests"
  "build/$suite-tests"
done
g++ -O2 -std=c++17 -Wall -Wextra -Wno-missing-field-initializers \
  tests/native_geometry.cpp -lvulkan -lX11 -o build/native-geometry-tests
build/native-geometry-tests
python3 -m unittest discover -s tests -p 'test_*.py'
