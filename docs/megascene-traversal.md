# Primary Megascene traversal

Issue #53 adds the full-geometry camera traversal for a fixed small or large
district. It reuses the separate validation, supervision, GPU and canonical
checkpoint boundaries described in [static replay validation](megascene-validation.md).
It does not qualify responsiveness or a capacity endpoint without the remaining
campaign evidence and calibration.

## Run the frozen route

The primary route is `traversal-v1`: startup and 120 warm-up frames at
`opening(0)`, followed by twelve 300-frame phases. Each phase holds its pose for
120 frames and interpolates eye and look coordinates for 180 frames to the next
pose. The last phase interpolates to itself. The fixed binary32 view of every
frame is stored in `schedule.json` and `camera.bin`; the worker reads those
bits directly. Picking and edits are disabled. A shorter traversal is rejected.

```sh
python3 scripts/megascene.py --case traversal --preset small --seed 45 \
  --threads 6 --resolution 1920x1080 --validation-only \
  --output build/traversal-validation --archive "$HOME/megascene-evidence"
python3 scripts/megascene.py --case traversal --preset small --seed 45 \
  --threads 6 --resolution 1920x1080 --validated build/traversal-validation \
  --output build/traversal-timed --archive "$HOME/megascene-evidence"
```

Validation and timing run in fresh processes. The runner compares every
validation frame and the timed initialization, warm-up, route reviews and
completion checkpoints. The logical payload includes the exact camera bits and
schedule identity. Per-body geometry hashes and work inventories must remain
unchanged through the final return. Native checks compare visible full-mesh
triangles against conservative culling, reject stale mesh slots, and require
camera motion to reuse unchanged full meshes and the world-fitted shadow map.

## Captures and review

The validation process alone captures startup, phase offset 60 of each route
phase, and completion. Capture pauses occur after rendered frames and outside
the fresh timed attempt. `review.json` binds each named feature to its capture
hash and records shadow extent, metres per texel and the minimum occupied-body
margin inside the shadow map. Every named feature starts pending. Missing
captures or assessments leave visual quality inconclusive; logical and native
rendering correctness remain separate from readability.

An operator can inspect `validation/captures/` and submit an assessments JSON
with one explicit entry per feature in `review.json`:

```json
{
  "schema": "megascene-feature-assessments/1",
  "views": {
    "opening": {
      "building silhouettes": {"geometry": "correct", "readability": "readable"},
      "span silhouettes": {"geometry": "correct", "readability": "readable"},
      "major shadows": {"geometry": "correct", "readability": "readable"}
    }
  }
}
```

The actual input must also name every other view and feature. Geometry is
`correct` or `incorrect`; readability is `readable`, `insufficient` or
`unassessable`. A nonpassing entry needs a `note`. An incorrect geometry entry
fails rendering correctness. Correct geometry with insufficient readability
fails visual quality. A passing visual-quality outcome requires every feature
to be marked correct and readable, every capture hash to match, and occupied
geometry to fit the recorded shadow map.

```sh
python3 scripts/megascene_review.py --bundle /path/to/archived/attempt \
  --assessments /path/to/assessments.json --reviewer "Reviewer name"
```

The command retains the raw assessment input and updates `review.json`,
`summary.json` and their hashes in `manifest.json`. Review the archived attempt,
which is the retained evidence source. This is a runtime and human observation,
not a formal Bend proof.
