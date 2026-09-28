# Static replay validation and canonical checkpoints

Issue #51 implements correctness evidence for the fixed static configuration.
It does not complete the other Megascene scenarios, instrumentation calibration,
visual feature review, performance qualification, or the parent implementation
acceptance matrix. Unsafe Bend geometry, the native renderer and these validators
are covered by runtime/reference tests, not formal proofs.

## Operator workflow

The ordinary static invocation now builds and archives actual artifacts, runs the
small independent reference worker and a complete separately supervised Vulkan
validation replay, then launches a fresh timed process. Both processes start with
empty world, transport and renderer caches. Validation never supplies an in-process
cache or preconstructed world to timing. Every process shares the campaign
allowance and resource/deadline policy. The default frozen schedule is startup,
120 warm-up frames and 3,600 measured frames; an explicitly shortened schedule
validates only that declared configuration.

To validate without launching a timed attempt:

```sh
python3 scripts/megascene.py --case static --threads 6 \
  --resolution 1920x1080 --validation-only \
  --output build/static-validation --archive "$HOME/megascene-evidence"
```

To use that validation for a new timed process with identical settings:

```sh
python3 scripts/megascene.py --case static --threads 6 \
  --resolution 1920x1080 --validated build/static-validation \
  --output build/static-timed --archive "$HOME/megascene-evidence"
```

`--validated` verifies retained runtime and validation evidence hashes. It rejects
changes in the executable, native library, shaders, generator, reference/checker
code, frozen inputs or schedule, fixed step, warm-up, profile, resolution, thread
count, deadline, controlled environment or recorded execution platform. It checks
sampled loaded host graphics-library hashes before launch and compares the actual
loaded host libraries, palette, device/driver and effective rendering settings
again after execution. Application libraries and shaders execute from the archive.
The host graphics stack remains a platform requirement, not a portable OS image.
A missing, corrupt or failed replay never becomes a reuse candidate.

`--runtime-from PATH` instead copies an archived static application runtime and
runs a **new validation**. The compiled workload and rendering/schedule settings
must match; the thread count may change. It is useful for checking 1/6/12 threads
against the exact same executable without recompiling. Each thread configuration
still has its own complete validation and fresh timed attempt:

```sh
python3 scripts/megascene.py --case static --threads 1 \
  --runtime-from build/static-timed --output build/static-1 \
  --archive "$HOME/megascene-evidence"
python3 scripts/megascene.py --case static --threads 12 \
  --runtime-from build/static-timed --output build/static-12 \
  --archive "$HOME/megascene-evidence"
python3 scripts/megascene_checkpoints.py --compare-threads \
  build/static-1 build/static-timed build/static-12 \
  --output build/static-thread-comparison.json
```

This comparison accepts only separately validated timed attempts. It compares
checkpoint and per-body hashes while preserving each attempt's actual work
inventory. Runtime bytes, schedule and settings must match except for thread
execution. Allocation addresses, mesh-slot locations and tree construction order
are absent from logical equality. Different cuboid or equivalent rectangle
partitions can have identical canonical geometry while reporting different work.

## Independent references and complete replay checks

The small reference suite expands only its deliberately small fixtures into a
cell-to-material map. A separate six-neighbor flood fill and exposed-unit-face
oracle check the actual production Bend constructors, component result, anchor
state, faces and triangle vertices. Fixtures cover signed coordinates, partial
face contact, hidden material interfaces, edge/corner separation, unanchored
material, protected support and cavities. Production cuboid connectivity or face
subtraction is never used as the dense oracle.

The large replay does not densely expand the district. Every frame reads actual
Bend leaves, branch bounds, body IDs/revisions, offsets/velocities and fresh face
and vertex lists. It checks branch summaries and node counts, integral bounds,
checked cell arithmetic, disjoint ownership, positive-area connectivity, anchors,
material conservation, exact drawable surface coverage and triangle winding.
Fresh Bend geometry must match the cached native transport. Every rendered frame
checks full native mesh slots and their material colors, draw-range ownership,
shadow membership and visibility against independent clipping of unculled mesh
triangles. The report checks expected cold-build/reuse transitions for full meshes,
proxy bookkeeping and world-fitted shadows. The static fixture has no edits or
motion transitions; none are claimed as validated by this slice.

Validation emits a compact `static_audit` digest and actual per-body work on every
intermediate frame. Named points also retain complete canonical payloads. Python
independently constructs the initial expected canonical payload from the checked
production inventory using sparse integer boundary sweeps. Every replay digest
must agree with that expected static state. Native/reference fixtures separately
reject missing/duplicate geometry, wrong winding and stale mesh data, so a matching
hash does not substitute for those checks.

## Exact checkpoint representation

The normative encoding is [megascene-evidence/1](megascene-evidence.md). Payloads
use `schema: megascene-checkpoint/1`, ASCII-sorted keys, no whitespace, canonical
decimal strings and finite binary32 bit strings. Signed zero in motion/view data
is preserved. Numeric JSON tokens, duplicate keys, escaped/noncanonical payload
bytes and characters outside the restricted vocabulary are rejected. SHA-256
hashes the exact canonical payload bytes, with no newline or embedded digest.
OpenSSL supplies SHA-256; its linked library is retained with the runtime.

The payload contains `action_outcomes` (empty for static), `bodies`, `budget`,
`cells`, `fixed_step`, `fragments`, `next_id`, `removed`, `schedule_sha256`, `schema`,
`status` and `view`. The view includes exact camera/aim bits and render dimensions.
Bodies are sorted by numeric ID and include `anchored`, `id`, `occupancy`,
`offset_m`, `revision`, `surface` and `velocity_m_s`.

Occupancy is `[x_lo, x_hi, y_slabs]`; a Y slab is
`[y_lo, y_hi, z_intervals]`; a Z interval is `[z_lo, z_hi, material]`.
Equal touching Z intervals merge, followed by equal adjacent Y and X slabs.
Empty slabs are omitted. Each surface group is
`[side, material, plane, strips]`, sorted numerically by those three labels.
Strips use the two-dimensional equivalent of the occupancy sweep with cyclic
axes `u=(side/2+1)%3` and `v=(side/2+2)%3`. Overlap and incorrect/missing drawable
coverage and winding are checked before normalization.

The enclosing record has `sha256`, `body_sha256`, `names`, `work` and normal
frame/attempt identity. `work` retains actual cells, protected cells, cuboids,
tree nodes, surface rectangles and vertices per owner, outside logical equality.
Named points are initialization and `review_opening` at startup, `warmup_end` at
the declared warm-up boundary, and completion on the last measured frame.
Coincident names share one payload. A zero-warm-up schedule checks warm-up end
at startup. Checkpoint construction, checking, hashing and emission take place
inside that frame's normal CPU work, before the corresponding render return;
they are never deferred to teardown or reconstructed from totals afterward.

## Evidence and outcomes

`validation.json` records applicable identities, independent reference results,
numeric bounds, invariant coverage, checked frame count, checkpoint catalog and
elapsed validation duration. The `validation/` directory retains that process's
manifest, stdout, reference fixtures, CPU/checkpoint records, resource evidence,
comparison and summary. `comparison.json` reports logical timed agreement, a separate
`representation_work` comparison, and the first
useful field/body mismatch with expected and actual values. A truncated or
incomplete attempt retains its usable prefix and cannot pass full correctness.

Correct state/native geometry evidence can pass independently of missing visual
feature review or calibration. `qualified_capacity`, `interactive_pass`,
responsiveness and overall benchmark qualification remain inconclusive in this
slice. Validation frame timings are validation cost, not performance samples.

A fixed-size X11 hint requests the declared dimensions. Resizing, changed surface
capabilities or an out-of-date swapchain still fails the attempt. The compositor
may return `VK_SUBOPTIMAL_KHR` while presentation succeeds with unchanged surface
capabilities; those results are explicitly recorded as `presentation_status`
without recreating the swapchain or changing the workload. This follows the
[Vulkan result semantics](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html).
Neither that status nor a successful CPU submission establishes physical display
latency or visual-quality qualification.

## Verification

```sh
make test
bend PROOF.bend
bend PROOF.bend --verdict
MEGASCENE_VULKAN_TEST=1 python3 -m unittest discover -s tests -p test_megascene_static.py -v
MEGASCENE_VULKAN_TEST=1 python3 -m unittest discover -s tests -p test_megascene_checkpoints.py -v
```

Run real Vulkan attempts without concurrent benchmark processes. Small native,
independent-reference and synthetic-report checks have distinct scopes. The
retained issue evidence identifies complete real configurations and unsuccessful
attempts separately; synthetic records never establish benchmark success.
See the [retained issue #51 evidence](validation/megascene-checkpoints/README.md)
for the complete 1/6/12-thread comparison, large replay, regression results and
archive identities.
