#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(bend version 2>/dev/null)" != 'bend 2.0.26' ]]; then
  echo 'The Vulkan demo is pinned to Bend 2.0.26.' >&2
  exit 1
fi
mkdir -p build
glslc --target-env=vulkan1.3 src/vulkan/scene.vert -o build/vulkan-scene.vert.spv
glslc --target-env=vulkan1.3 src/vulkan/scene.frag -o build/vulkan-scene.frag.spv
g++ -O2 -std=c++17 -fPIC -shared -Wall -Wextra -Wno-missing-field-initializers \
  src/vulkan/native.cpp -lvulkan -lX11 -o build/libvoxel_vulkan.so
bend src/demo_vulkan.bend -o build/voxel-vulkan
