# Irregular destruction history

`--case history` runs the accepted 120-cut `history-v1` schedule in a separate
Megascene process. It uses 120 warm-up frames, 3,600 measured frames, the fixed
binary32 simulation step, full body meshes, the existing ground and shadow
profile, and a separate complete validation replay before a timed attempt.

```sh
python3 scripts/megascene.py --case history --preset small --seed 45 \
  --threads 6 --resolution 1920x1080 \
  --archive "$HOME/megascene-history-evidence" \
  --output build/megascene/history/first
```

Use a new output directory for each attempt. The durable archive retains the
actual executable, native library, shaders, sources, frozen inputs, per-frame
CPU/GPU records, action records, allocation/resource records, comparison and
captures. `--validation-only` performs the separate complete replay without a
timed attempt. The accepted 300-second case deadline and campaign allowance
still apply. A stopped attempt retains its committed prefix and is classified
as incomplete; it cannot be reported as a benchmark pass.

## Frozen actions and state checks

The schedule resolves all 120 targets and cameras before launching the worker.
One 20 cm cut occurs at measured ordinal `12*k` for `k=0..119`. Its exact
binary32 coordinates remain fixed, including the moved-beam target computed
after twelve simulation steps. Earlier terrain damage is revisited, support
paths release spans, and later bridge cuts address the remaining anchored
stubs. The independent sparse preflight follows the evolving occupancy and
requires fresh unprotected material at every cut. It records the exact removed
cells, expected component count, and pre-edit owner visibility for both fixed
presets and seeds 45/46. The accepted totals are 2,440 removed cells on small
and 2,472 on large.

The actual replay records every action outcome and edit-stage interval. A
rejection, no-op, missing action or wrong removal invalidates completion. The
checkpoint checker independently subtracts material from the current owner,
finds positive-face connected components, and maps their canonical occupancy
to fresh lifetime IDs. It checks intermediate anchors, material, exposed
surfaces, inherited motion, next ID, fragment count, actual cuboid/surface/
vertex work, native meshes, proxy caches and shadows. Its validation replay
checks every frame; the timed replay retains all 120 edit checkpoints, named
checkpoints after cuts 12/48/120 (absolute frames 253/685/1549), initialization,
warm-up, the far overview at frame 1681 and completion.

Validation caches an already checked body's canonical geometry only while its
raw boxes, faces, vertices, bounds, revision and anchor match exactly. It still
reads and records motion each frame, checks world occupancy and native work,
and recomputes geometry if any of those bytes change. This keeps the complete
1080p validation within the fixed case deadline without weakening the check
on changed geometry.

Ordinary and edit frame populations remain separate. The report also retains
named early/middle/late history intervals, the moving-span window, overview
transition and settled tail, with CPU and available GPU distributions. Settled
tail samples never stand in for moving-span samples. Successful correctness and
completion checks do not qualify responsiveness or an architectural capacity
endpoint: calibration, population evidence and visual assessment have their
own statuses.

Validation captures the opening, every cut, the far overview and completion
outside the timed attempt. Each named feature remains pending until reviewed
against its retained capture. Native geometry checks and visual quality are
reported separately.

## Reference and proof scope

The focused 20-frame Bend fixture executes two overlapping terrain cuts, two
span support cuts and a cut on the released beam. A dense cell oracle checks
its intermediate material, connectivity, exposed unit faces, ownership,
motion and IDs. Synthetic action records check rejected, missing, no-op and
mis-timed report paths. The full replay checker stays sparse because the
district terrain contains millions of cells. Runtime and native checks cover
unsafe-dependent properties; they are not formal proofs.

```sh
python3 -m unittest discover -s tests -p test_megascene_history.py -v
make test
bend PROOF.bend
bend PROOF.bend --verdict
```

The accepted [workload annex](megascene-workload.md),
[evidence contract](megascene-evidence.md), and
[supervision policy](megascene-supervision.md) define the broader suite.
