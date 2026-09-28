# Bounded picking evidence, 2026-09-28

Issue #54's small, seed-45 `picking-v2` replay completed at 1920 × 1080 on the
Ryzen 5 1600 / GeForce GTX 1660 Linux/X11 host. The primary six-thread attempt
uses full body geometry, baseline daylight, 2048 × 2048 shadows and immediate
presentation. Its 74,420-byte camera input is byte-for-byte identical to the
archived, accepted `traversal-v2` camera input from issue #53 (SHA-256
`179768549aacade946ba42674754defa4eee8f1a5559ebc46f126abd71125d6a`).
The complete picking schedule SHA-256 is
`7039e4d24f63d3e8e29faa0f0bec872bf695366538df9ee3e439b62fd8099881`.

The separate validation replay passed all 3,721 frames, then a fresh timed
process completed startup, 120 warm-up frames and 3,600 measured frames. Both
executed exactly 600 required hits, 120 required sky misses and 3,001 disabled
samples. Actual ray bits, winning owner/material, point, distance and kind
matched the frozen schedule. All 16 named checkpoint occurrences and 3,721
native frame audits passed; world state, body geometry, full meshes, proxy
bookkeeping and the shadow cache stayed unchanged. Opening and completion
captures are byte-identical.

The native small reference suite agrees with independent rational face and
unit-cell intersections. It covers empty/ground/protected rays, signed cells,
translated bodies, parallel bounds, nearest ownership, an interior origin and
strict reach. A distance of 255.99998474121094 m hits; exactly 256 m and the
next tested distance beyond it miss. The tests reject a separate case where an
exact 256 m endpoint and tiny positive origin produce an inexact subtraction
that would change the required hit into a miss. Actual operation guards reject
unsupported offsets and coordinate conversions before unsafe traversal.
These are runtime/reference checks, not formal proofs of unsafe or native code.

## Thread comparison

Each thread configuration completed its own full validation replay and a fresh
3,600-frame timed attempt using the same frozen workload and runtime bytes.
The [thread comparison](thread-comparison.json) passes exact checkpoint and
geometry equality across 1, 6 and 12 threads; each also retains all 720 enabled
picking results. These durations are observations, not calibrated speedup claims.

| Threads | Ordinary interval (s) | State/rendering | Timed attempt |
| --- | --- | --- | --- |
| 1 | 4.346457293 | Pass | `00bea2d2-9d11-4d0d-bb16-f6ba77a88249` |
| 6 | 4.247100903 | Pass | `3aa0a13d-7de7-4f11-ba6e-ea93c0e0611f` |
| 12 | 4.375959631 | Pass | `d0279f03-3288-42b0-b759-5df4868de1eb` |

All three intervals remain below the ten-second qualification minimum. The
named visual review below applies to the primary six-thread captures; the
additional thread runs retain their own captures with visual review pending.

## Captures and review

The [contact sheet](contact-sheet.png) shows all 14 required review views.
The [first cavity](cavity-first.png) and [return cavity](cavity-return.png)
retain the bridge, lower floor, rim and sidewalls with the actual floor aim.
The wall, doorway/interior wall and upper lobe captures show their required
hits; the sky capture has no aim overlay. Codex reviewed the named features,
including full-resolution doorway, assembly and cavity views, and recorded
all 41 assessments as correct and readable. This is a visual judgment, not
separate user confirmation or a formal proof. Fine shadow texel edges remain
coarse, without hiding the required major features.

[review.json](review.json) and [assessments.json](assessments.json) retain the
per-feature notes and raw capture hashes. Their capture paths are relative to
the durable primary archive below. Rendering correctness, state correctness
and the primary visual review passed independently of performance qualification.

## Retained artifacts and limitations

The primary timed attempt is `3aa0a13d-7de7-4f11-ba6e-ea93c0e0611f`; its
separate validation replay is `452e440b-60f7-42b2-ae53-5b82cf3e4f26`.
The primary archive is:

```text
/home/aivv/megascene-issue54/a9588819-aeda-4415-8b95-8ce334d8e499/97412b9d-1465-4021-9611-0fff0124462f/3aa0a13d-7de7-4f11-ba6e-ea93c0e0611f
```

All 86 runtime/input artifacts and 60 evidence-file hashes were verified after
visual review. The archived executable, shared libraries, shaders, source,
frozen inputs, independent reference worker, validation, timed CPU/GPU/resource
streams and raw captures remain retrievable. [results.json](results.json)
contains the identities, outcomes and independent reference details.

The six-thread ordinary-frame interval was 4.247100903 s. It is below the
required 10 seconds, and instrumentation calibration is unavailable. This is
**not a benchmark pass or qualified capacity endpoint**. The frozen schedule
was neither lengthened nor pooled to satisfy a sample threshold.

Six earlier incomplete attempts remain in the same campaign and in
`results.json`, including a profiled diagnostic and an unsuccessful Btrfs
no-copy-on-write storage experiment. They stopped on resource-monitor
freshness, not incorrect picking or a demonstrated memory limit. Profiling
found 22.0 seconds of synchronous durability flushes inside supervision.
The fix moves flushes to one I/O worker while preserving unbuffered append-only
writes, committed shared slots, a final durability barrier and every resource
threshold. The successful runs use the original storage flags. The primary
timed host/heap maximum sample gaps were 100.10/124.60 ms, below the unchanged
one-second freshness limit; its final durability barrier completed.

Verification: `make test` passed 76 Python tests (two optional tests skipped)
and all Bend/native suites. The eight picking tests also passed after the
foreign-effect ownership cleanup. Both `bend PROOF.bend` and
`bend PROOF.bend --verdict` passed. Retained logs are [tests.log](tests.log),
[picking-tests.log](picking-tests.log), [proof.log](proof.log) and
[verdict.log](verdict.log).
