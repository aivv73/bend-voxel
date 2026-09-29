# Archived static and localized reproduction

Issue #63 adds recovery to the public Megascene runner. Supply the archived
attempt directory named by its manifest's `reproduction.archive` and a new
durable archive root. The output directory must also be new and separate.

```sh
python3 scripts/megascene.py \
  --reproduce-from "$HOME/megascene-evidence/CAMPAIGN/SERIES/ATTEMPT" \
  --archive "$HOME/megascene-reproductions" \
  --output build/megascene/reproduced-attempt
```

The runner accepts only these three paths and an explicit
`--additional-allowance` when an existing campaign requires it. Case, preset,
seed, threads, profile, resolution, frame counts and schedule come from the
source manifest. A changed option is rejected and retained as a failed attempt.
The current generator does not create replacement world inputs or a new camera
schedule.

Recovery requires the source's recorded durable location, its real
`megascene-evidence/1` manifest, the executable and loader, linked libraries,
application native library, shaders, generated Bend entry, generator script,
generation inputs and frozen schedule. A localized run also requires its frozen
camera file and edit reference worker. Every listed runtime artifact is hashed
before and after copying. Files are created exclusively, with executable modes
preserved. A partial copy remains in the failed attempt directory, and a later
attempt receives a new identity. Archived evidence used as a comparison baseline
is hash-checked and retained under `source_evidence/`.

The restored bundle runs a fresh complete validation replay and a fresh timed
replay through the same resource supervisor. `manifest.json` records the new
host environment, actual invocation, source attempt and validation identities.
`reproduction_comparison.json` compares the original and reproduced initial
inventories, canonical state and per-body geometry checkpoints, plus the saved
timed checkpoint payloads. A mismatch records the first differing field and
both values. `summary.json` reports reproduction separately from performance
qualification. Elapsed times are observations and are not compared.

Source and recovered failed or incomplete attempts remain on disk with their
committed streams, damaged tails, exit status and completed prefixes. Missing,
tampered or inaccessible files, a changed option, failed validation or a
checkpoint mismatch cannot produce a reproduction pass. Artifacts left only in
disposable build output do not qualify as a durable source. The host graphics
stack is a recorded platform dependency; this is not an OS image or a promise
of cross-platform tolerance. Unsafe and native behavior is checked with runtime
and independent reference evidence, not presented as a formal proof.
