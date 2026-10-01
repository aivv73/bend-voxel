#!/usr/bin/env bash
set -euo pipefail
test "$#" = 2 && test "$1" = --gpu && test "$2" = off
test "$VOXEL_STRESS" = 1 && test "$VOXEL_STRESS_PRESENT" = unpaced
if [[ -n ${STRESS_LOCALE_FILE:-} ]]; then printf '%s\n' "${LC_ALL-unset}" > "$STRESS_LOCALE_FILE"; fi
if [[ -n ${STRESS_TRACE:-} ]]; then
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$PWD" "$VOXEL_STRESS_VIEW" "$VOXEL_STRESS_WARMUP" "$VOXEL_STRESS_MEASURED" "$VOXEL_STRESS_EDIT_EVERY" "$VOXEL_BODY_BUDGET" "$VOXEL_RESOLUTION" "${CUDA_HOME:-unset}" >> "$STRESS_TRACE"
fi
case ${STRESS_PRESENT:-immediate} in
  missing) ;;
  mixed) printf 'stress_present_mode,immediate\nstress_present_mode,mailbox\n' >&2 ;;
  repeat) printf 'stress_present_mode,mailbox\nstress_present_mode,mailbox\n' >&2 ;;
  *) printf 'stress_present_mode,%s\n' "${STRESS_PRESENT:-immediate}" >&2 ;;
esac
printf 'fixture stderr é\n' >&2
printf 'init,500000\nsurface,1200\nworld,803970,6,2034,%s\n' "$VOXEL_BODY_BUDGET"
if [[ ${STRESS_SLOW:-0} = 1 ]]; then
  if [[ -n ${STRESS_PID_FILE:-} ]]; then printf '%s\n' "$$" > "$STRESS_PID_FILE"; fi
  if [[ ${STRESS_IGNORE_TERM:-0} = 1 ]]; then trap '' TERM; fi
  sleep 30
fi
if [[ ${STRESS_SIGNAL:-0} != 0 ]]; then kill -"$STRESS_SIGNAL" "$$"; fi
if [[ ${STRESS_EXIT:-0} != 0 ]]; then exit "$STRESS_EXIT"; fi
solids=803970
total=$((VOXEL_STRESS_WARMUP + VOXEL_STRESS_MEASURED))
for ((index=0; index<total; index++)); do
  end=$(((index + 1) * 1000))
  editing=0
  if ((VOXEL_STRESS_VIEW == 3 && VOXEL_STRESS_EDIT_EVERY > 0 && index >= VOXEL_STRESS_WARMUP)); then
    relative=$((index - VOXEL_STRESS_WARMUP))
    if ((relative % VOXEL_STRESS_EDIT_EVERY == 0 && relative / VOXEL_STRESS_EDIT_EVERY < 6)); then editing=1; fi
  fi
  solids=$((solids - editing * 20))
  printf 'frame,%s,1000,%s,0\n' "$end" "$solids"
  if ((editing)); then
    printf 'stage,%s,100,100,100,0,0,0,700,0\n' "$end"
    printf 'vulkan_stage,%s,100,100,100,100,100,100,100,0,0\n' "$index"
    printf 'edit,%s,%s,20,1,100,100,100,0\n' "$end" "$((end - 1000))"
    printf 'cut,%s,1000,1,20\n' "$((end - 1000))"
  else
    printf 'stage,%s,0,0,0,0,0,0,1000,0\n' "$end"
    printf 'vulkan_stage,%s,0,0,0,0,0,0,0,1000,0\n' "$index"
  fi
  rebuilt=$editing
  uploaded=$((editing * 16000))
  if ((index == 0)); then rebuilt=6; uploaded=300000; fi
  printf 'mesh_cache,%s,%s,6,6,62046,%s\n' "$index" "$rebuilt" "$uploaded"
  printf 'lod_cache,%s,0,0,0,6,0\nbodies,%s,6,0,0,0.000000\n' "$index" "$index"
  night=0
  if ((VOXEL_STRESS_VIEW == 6)); then night=1; fi
  refresh=$editing
  if ((index == 0)); then refresh=1; fi
  printf 'lighting,%s,%s,%s\n' "$index" "$night" "$refresh"
  case $VOXEL_STRESS_VIEW in
    0) ;;
    1) printf 'view,%s,%s,11,25,-2.8084,-0.3,0,0,0,0\n' "$index" "$index" ;;
    2) printf 'view,%s,9,11,25,-2.8084,-0.3,1,%s,1,0\n' "$index" "$index" ;;
    *) printf 'view,%s,9,11,25,-2.8084,-0.3,0,0,0,0\n' "$index" ;;
  esac
done
