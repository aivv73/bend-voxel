# Selected DDA cache design

Choose candidate 3's single retained subtree, with candidate 2's fused anchor selection and initial leaf lookup. The independent cross-judge scored candidates 2 and 3 at 17/20 and candidate 1 at 12/20. Parent scoring agrees. Candidate 3 resolves termination without a mutually recursive continuation.

The private cache describes one actual root descent with a subtree, cyclic split axis, absolute low coordinate, and span. It belongs to one ray and one immutable grid. Carry its fields through the private trace loop. Seed or refresh it with a bounded prefix descent, returning the exact leaf Region at the same time. Reuse Tree.region below the anchor while the next absolute cell lies within all six half-open bounds. Check containment before subtracting unsigned coordinates. Refresh from the root on a cache miss. Preserve the existing empty outside Region.

Use candidate 1's reachable ancestry invariant for formal reasoning. Anchor bounds never feed Crossing.region. Keep crossing arithmetic, Axis.count, Trace.walk, frame scheduling, and public interfaces unchanged. Cache depth is one private tuning definition, initially six cyclic splits. Benchmark alternate values three and nine using separately frozen source snapshots and binaries if six is promising. Do not add public API variants or engine environment reads merely for tuning.

Reject the full ancestry arrays for this first attempt because every ray would initialize 128 tree slots and 1024 metadata slots. A reduction in descent cannot establish a gain against those ownership and allocation costs.

Prove full Region preservation for anchor selection through structural induction. A same-seed-cell proof alone does not establish lookup preservation for subsequent cells. Seek the reachable ancestry plus containment theorem with honest arithmetic preconditions. If unavailable within this attempt, record cross-cell preservation as runtime verification and retain no claim of formal trace equivalence.

Inspect emitted C for borrowed descendant lookup, retained handles, state size, and allocation on each crossing. Acceptance comes from exact real-runtime hits and image bytes plus complete-frame alternating release measurements, including the GPU lane separately.

The fresh CPU1 profiling run rendered twelve complete native frames, including four warmups and eight measured frames. Its diagnostic samples place 42.73 percent in Grid.region tree descent, 25.11 percent in Axis.advance, and 16.74 percent in Crossing.region. The profile is not release timing evidence. Source mapping and raw output are retained in baseline.c, baseline-gprof.txt, and baseline-profile-run.txt.
