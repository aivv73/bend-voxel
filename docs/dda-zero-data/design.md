# Zero-event guard synthesis

The parent and cross-judge both score the helper package 9/10 and the two thunk packages 10/10. Candidate 3 is the design base because it adds no importable helper API and explicitly types affine closures. Candidate 1 provides the monomorphic Boolean-helper fallback and full-call-path inspection. Candidate 2 confirms the exact Base selector quantities and the closure-cost rejection gate. All three packages were read; no runner dropped out. User model overrides make the entire panel gpt-6.1-sol.

Both forms check, pass the kernel, and pass seven exact CPU scans plus CPU/GPU image parity. Actual thunk lowering retains heap allocation and indirect closure application in every predicate call, visible in thunk-guard.c:51291 and :51323. The scalar helper prototype preserves the count without numeric reconstruction, and its ordinary native axis code contains direct zero branches and no surviving wrapper calls. These observations replace the initial source-size preference with the helper fallback for the next performance experiment. No measured thunk slowdown is claimed yet.

The selected helpers remain adjacent to the unchanged Axis.before and Axis.advanced wrappers. Only wrappers derive the zero Bool. There is no new caller flag, data type, scheduling choice, or F32 order. Bend exports definitions, so helper privacy is a convention. This is an accepted small internal surface cost for a parameter-only branch that passes scalars rather than closures. Later source changes need real compiler-binding checks before diagnostics.

Remaining gates are exact helper work counters, matched complete-frame CPU/GPU measurements, and independent final evidence review. The helper form is not retained until the available lanes satisfy the performance gate. The smaller thunk form remains preserved as a checked prototype; its final disposition needs either a stated compiler-cost rejection or measured frame data.

## Measured disposition

The Boolean helpers are rejected. Eight measured frames in each of five alternating process pairs increase GPU fork-six medians from 502.375 to 525.375 ms and fork-seven medians from 509.5 to 538 ms. Every pair regresses in both decompositions, with non-overlapping ranges.

The affine thunks are rejected. Four measured frames in each of five alternating process pairs increase CPU12 medians from 105.75 to 387.25 ms, with every pair slower and non-overlapping ranges. The observed closure machinery explains a plausible added cost; this is not a measurement of each instruction's contribution.

After counting the opportunity at both guard sites, the parent narrowed the change to the existing Axis.next moving branch in Axis.advanced. No helper or new data shape is added. Its general Boolean crossing-equivalence law passes ordinary and kernel checks; seven exact ray scans and available-lane image comparisons pass. Its two GPU decompositions have overlapping baseline/candidate timing ranges. CPU retention gates and final evidence review remain pending. The initial scores were design judgments, not measured performance rankings.

The existing-branch candidate is also rejected after complete CPU measurements and longer CPU1/CPU6 follow-ups. All ten CPU6 paired runs are slower, CPU1 medians rise in both batches, and no lane establishes a frame-time win. Root engine and proof files remain unchanged. The final report records source identities, all checked/rejected shapes, actual native skipped arithmetic, and separate release timings. Independent final evidence review is the remaining delivery gate.
