#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
bend tests/stress-parser.bend -o build/stress-parser-tests
bend tests/stress-metrics.bend -o build/stress-metrics-tests
build/stress-metrics-tests --threads 1 --gpu off
temporary=$(mktemp -d "${TMPDIR:-/tmp}/bend-stress-parser.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
fixtures=tests/fixtures/stress
parse() { build/stress-parser-tests --threads 1 --gpu off -- "$@"; }
compare() {
  jq -S . "$1" > "$temporary/actual"
  jq -S . "$2" > "$temporary/expected"
  cmp "$temporary/actual" "$temporary/expected"
}
for name in ordinary reordered atelier night; do
  case $name in
    ordinary|reordered) every=1; mode=static; world=0;;
    atelier) every=1; mode=carve; world=1;;
    night) every=0; mode=night; world=1;;
  esac
  parse "$fixtures/$name.csv" 1 1 "$every" "$mode" "$world" 0 > "$temporary/$name.json"
  compare "$temporary/$name.json" "$fixtures/$name.json"
done
reject() {
  parse "$temporary/bad.csv" 1 1 1 carve 1 0 > "$temporary/rejected.json"
  jq -e '.pass == false and (.errors | length > 0)' "$temporary/rejected.json" > /dev/null
}
for mutation in \
  '/^surface,/d' \
  '/^stage,2500,/d' \
  '/^vulkan_stage,1,/d' \
  '/^cut,/d' \
  '/^world,/d' \
  '/^mesh_cache,1,/d' \
  '/^lod_cache,1,/d' \
  '/^bodies,1,/d' \
  '/^lighting,1,/d' \
  's/world,803970,6/world,803970,5/' \
  's/stage,2500,100,100,100,0,0,0,1100,100/stage,2500,100,100,100,0,0,0,1100,101/' \
  's/vulkan_stage,1,100,100,100/vulkan_stage,1,100,400,100/' \
  's/lighting,1,0,1/lighting,1,0,0/' \
  's/lighting,1,0,1/lighting,1,1,1/' \
  's/frame,2500,1500,803950,0/frame,2500,1500,803971,0/' \
  's/mesh_cache,1,1,6/mesh_cache,1,3,6/' \
  's/mesh_cache,1,1,6,6/mesh_cache,1,1,6,7/' \
  's/lod_cache,1,0,0,0,6,0/lod_cache,1,0,7,0,6,0/' \
  's/bodies,1,6,0,0,0.000000/bodies,1,5,0,0,0.000000/' \
  's/bodies,1,6,0,0,0.000000/bodies,1,6,1,0,0.000000/' \
  's/bodies,1,6,0,0,0.000000/bodies,1,6,0,0,0.1/' \
  's/bodies,1,6,0,0,0.000000/bodies,1,6,0,0,nan/' \
  's/view,1,9,11,25,-2.8084,-0.3,0/view,1,9,11,25,-2.8084,-0.3,1/' \
  's/view,1,9,11/view,1,inf,11/' \
  's/view,1,9,11/view,1,1e999,11/' \
  's/view,1,9,11/view,1,0x1,11/' \
  's/frame,1000,1000/frame,1000,4294967296/' \
  's/frame,1000,1000/frame,1000,-1/' \
  's/frame,1000,1000/frame,1000,invalid/'; do
  sed "$mutation" "$fixtures/atelier.csv" > "$temporary/bad.csv"
  reject
done
for tag in frame stage vulkan_stage init surface edit cut; do
  cp "$fixtures/atelier.csv" "$temporary/bad.csv"
  sed -n "/^$tag,/ {p;q;}" "$fixtures/atelier.csv" >> "$temporary/bad.csv"
  reject
done
parse --empty 1 1 1 static 0 0 | jq -e '.pass == false' > /dev/null
parse "$fixtures/ordinary.csv" 1 1 1 static 0 7 | jq -e '.pass == false and (.errors | index("Process exited 7") != null)' > /dev/null
parse "$fixtures/ordinary.csv" 1 0 1 static 0 0 | jq -e '.pass == false' > /dev/null
for sign in '-+1' '--0' '- 1'; do
  sed "s/init,500000/init,$sign/" "$fixtures/ordinary.csv" > "$temporary/bad.csv"
  parse "$temporary/bad.csv" 1 1 1 static 0 0 | jq -e '.pass == false' > /dev/null
done
sed 's/init,500000/init,9007199254740995/' "$fixtures/ordinary.csv" > "$temporary/wide.csv"
parse "$temporary/wide.csv" 1 1 1 static 0 0 | jq -e '.pass == true and .initialization_ms == 9007199254740.994' > /dev/null
sed 's/init,500000/init,-0/' "$fixtures/ordinary.csv" > "$temporary/negative-zero.csv"
parse "$temporary/negative-zero.csv" 1 1 1 static 0 0 | jq -e '.pass == true and .initialization_ms == 0' > /dev/null
sed 's/init,500000/init,５０００００/' "$fixtures/ordinary.csv" > "$temporary/unicode.csv"
parse "$temporary/unicode.csv" 1 1 1 static 0 0 > "$temporary/unicode.json"
compare "$temporary/unicode.json" "$fixtures/ordinary.json"
parse "$fixtures/ordinary.csv" 1 1 1 static 0 7 | jq -e 'keys == ["errors", "pass"]' > /dev/null
sed 's/1000/"1000"/g; s/2500/"+2_500"/g' "$fixtures/ordinary.csv" > "$temporary/quoted.csv"
parse "$temporary/quoted.csv" 1 1 1 static 0 0 > "$temporary/quoted.json"
compare "$temporary/quoted.json" "$fixtures/ordinary.json"
sed 's/$/\r/' "$fixtures/ordinary.csv" > "$temporary/crlf.csv"
parse "$temporary/crlf.csv" 1 1 1 static 0 0 > "$temporary/crlf.json"
compare "$temporary/crlf.json" "$fixtures/ordinary.json"
sed 's/^cut,/attempt,/' "$fixtures/ordinary.csv" > "$temporary/attempt.csv"
parse "$temporary/attempt.csv" 1 1 1 static 0 0 > "$temporary/attempt.json"
compare "$temporary/attempt.json" "$fixtures/ordinary.json"
cat > "$temporary/vulkan-overflow.csv" <<'EOF'
init,0
surface,0
frame,1,1,0,0
stage,1,0,0,0,0,0,0,0,1
vulkan_stage,0,4294967295,1,0,0,0,0,0,0,0
EOF
parse "$temporary/vulkan-overflow.csv" 0 1 0 static 0 0 | jq -e '.pass == false and (.errors | .[0] | startswith("Vulkan detail exceeds frame effect"))' > /dev/null
sed 's/mesh_cache,1,0,6/mesh_cache,1,1,6/' "$fixtures/night.csv" > "$temporary/bad.csv"
parse "$temporary/bad.csv" 1 1 0 night 1 0 | jq -e '.pass == false' > /dev/null
parse "$temporary/bad.csv" 1 1 0 night 1 0 | jq -e '.night_frames == 2 and .shadow_refreshes == 1 and .initial_assemblies == 6 and .meshes_rebuilt == 1' > /dev/null
sed 's/lod_cache,1,0,0,0,6,0/lod_cache,1,0,0,1,6,0/' "$fixtures/night.csv" > "$temporary/bad.csv"
parse "$temporary/bad.csv" 1 1 0 night 1 0 | jq -e '.pass == false' > /dev/null
sed 's/lighting,1,1,0/lighting,1,1,1/' "$fixtures/night.csv" > "$temporary/bad.csv"
parse "$temporary/bad.csv" 1 1 0 night 1 0 | jq -e '.pass == false' > /dev/null
parse "$temporary/bad.csv" 1 1 0 night 1 0 | jq -e '.night_frames == 2 and .shadow_refreshes == 2 and .initial_assemblies == 6' > /dev/null
cat > "$temporary/zero.csv" <<'EOF'
init,0
surface,0
frame,0,0,0,0
stage,0,0,0,0,0,0,0,0,0
vulkan_stage,0,0,0,0,0,0,0,0,0,0
EOF
parse "$temporary/zero.csv" 0 1 0 static 0 0 | jq -e '.pass == false and (.errors | index("No measured frame time") != null) and .throughput_fps == null' > /dev/null
printf 'Stress parser complete reference reports and malformed/world/cache checks passed\n'
