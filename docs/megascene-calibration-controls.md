# Diagnostic calibration controls

Issue #64 adds `--calibration on|off` to primary static and history Vulkan
replays. Both modes use the same executable, native library, shaders, frozen
schedule, full geometry, resolution, preallocated shared reference recorder,
supervisor drain, resource monitor and Vulkan allocation ledger. The mode is an
environment setting recorded in the manifest. Use `--runtime-from` with the
first retained attempt to keep the application artifacts byte-identical across
the pair; each mode still performs its own complete validation replay.

An **on** control keeps the full qualifying instrumentation path. An **off**
control disables detailed CPU stage and ordinary logs, GPU queries, intermediate
checkpoint construction, detailed inventory transitions and native audits. It
retains frame and edit boundaries, population labels and actual scalar action
outcomes through the same common recorder as on. The supervisor persists
committed records during execution and after worker loss. Initial and final
canonical checkpoints are retained; the final off checkpoint runs after the
last measured frame boundary. The archive labels omitted fields `disabled`.

The off summary's `endpoint_agreement` compares those checkpoints and action
outcomes with its separately validated replay. It explicitly leaves actual
intermediate-state equality unproven. Its state correctness, capacity and
interactive outcomes remain inconclusive, and off controls cannot enter
benchmark passes or search endpoints. A gap, overflow, missing committed record,
resource/accounting failure, or failed checkpoint invalidates the control.

Complete 120/3,600 controls require `--calibration-peer-validation` naming a
retained successful validation of the opposite mode. Prepare both modes with
`--validation-only` before launching the first control. A control may reuse its
own prepared replay with `--validated`; the runner verifies both validation
artifacts and the peer's workload, runtime hashes and complete frame count.
This gate applies before a complete control can start.

For a bounded development smoke check, use a short static schedule and a new
output directory per attempt:

```sh
python3 scripts/megascene.py --case static --calibration off --preset small \
  --seed 45 --threads 6 --warmup 1 --frames 2 \
  --archive "$HOME/megascene-evidence" --output build/calibration-off
python3 scripts/megascene.py --case static --calibration on --preset small \
  --seed 45 --threads 6 --warmup 1 --frames 2 \
  --runtime-from build/calibration-off \
  --archive "$HOME/megascene-evidence" --output build/calibration-on
python3 scripts/megascene_calibration.py --off build/calibration-off \
  --on build/calibration-on
```

The paired reader requires matching configuration and runtime artifact hashes,
successful endpoint evidence and identical scalar action outcomes. It reports
only the limited equality established by those records. A shortened schedule
does not satisfy the accepted calibration protocol. For a qualifying control
series, use the complete 120 warm-up and 3,600 measured frames at 1920 × 1080,
and run the accepted off/on/on/off/off/on order for each static/history preset
and thread configuration. The separate calibration analysis and performance
qualification follow the [accepted handoff](megascene-spec.md#accepted-calibration-protocol).

The synthetic report fixtures in `tests/test_megascene_calibration.py` cover
missing checkpoints, corrupted disabled fields, worker loss, recorder gaps,
resource omission and mismatched endpoint hashes. The supervisor tests exercise
retrieval of committed shared records after a worker crash. Runtime and native
properties are supported by those fixtures and real Vulkan replays, not by
formal proofs that depend on unsafe definitions.
