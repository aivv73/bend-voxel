# Megascene evidence ladder

Use this ladder to choose the strength and scope of a Megascene claim. Start by auditing retained evidence, then execute only the missing work needed for the requested claim. The [accepted handoff](../../../../docs/megascene-spec.md), [evidence contract](../../../../docs/megascene-evidence.md) and [project laws](../../../../LAWS.bend) remain authoritative; this ladder organizes their requirements without changing them.

Every claim names the actual runtime/input/schedule hashes, case, scale, seed, threads, resolution, profile, fragment budget and recorded host graphics environment. A change to those inputs requires the applicable fresh validation or an explicitly supported reuse check. A different cuboid partition can preserve canonical geometry while changing representation work; retain both.

## The rungs

| Rung | Claim supported | Required evidence and promotion gate |
| --- | --- | --- |
| **E0 — Identity and execution contract** | The candidate and its evidence are identifiable and retrievable. | Pinned Bend/toolchain, requested/effective settings, frozen schedule, real runtime/source/library/shader bytes and SHA-256, host/device provenance, fresh output, established durable archive and available declared allowance. Missing or mismatched identity blocks promotion. |
| **E1 — Laws and independent fixtures** | Safe laws check; the tested unsafe/native invariants agree with independent references and negative fixtures. | `bend PROOF.bend`, supported `--verdict`, and passing runtime/native/Python suites. Dense small references cover occupancy/material, connectivity, surfaces/winding, picking, edits, motion and rollback. Injected failures must produce their specified classifications and retained evidence. Formal claims stop at safe definitions. |
| **E2 — District admission** | This declared initial district is valid. | Actual allocator/tree/face/vertex output; checked numeric bounds, owners, disjoint occupancy, anchors, connectivity, material and independent surface/vertex results. Admission passes for the exact scale/seed/thread configuration. It establishes initialization only. |
| **E3 — Real Vulkan smoke** | This declared bounded configuration starts, renders and exits correctly. | Real resource/device preflight; separate validation and timed processes; initial/state/native mesh checks; GPU evidence when claimed; requested opening capture and review; zero exit, final durability barrier and owned-process cleanup. A `1/2` static schedule is credited only as its declared development prefix. |
| **E4 — Complete behavioral replay** | This complete case preserves its specified state and native geometry through every required operation. | Separate complete configuration-specific validation plus fresh timed replay; accepted startup/120 warm-up/3600 measured schedule; independent intermediate checks and exact timed canonical checkpoints. All required rays, cuts and motion windows occur. Missing/no-op/rejected required actions or a retained prefix cannot pass a positive full-case claim. |
| **E5 — Named visual fidelity** | This case's required features are correctly rendered and readable. | Every required original capture, view/feature identity and hash; shadow fit/texel evidence; explicit geometry/readability assessments through `megascene_review.py`. Pending views block visual qualification. Preserve an insufficient overview; only an explicitly linked same-state supplementary view can cover its readability. |
| **E6 — Repeatability, recovery and failure retention** | The tested scope is repeatable, its runtime is recoverable, and failures retain trustworthy evidence. | Canonical world/per-body geometry equality at 1/6/12 threads where required, actual work inventories, eligible independent repeated processes, archive reproduction comparisons, and reference/supervisor failure fixtures. Reproduction uses archived application bytes and frozen inputs, with fresh validation/timing. Timings need not be equal. |
| **E7 — Functional implementation acceptance** | The accepted implementation checklist is complete on the archived host. | All 45 positive configurations with complete validation/timing and E5 fidelity, required identical repeats, admission seed coverage, independent/negative fixtures, reproduction, Light Atelier compatibility and faithful execution of the prescribed calibration protocol. The separate reviewed decision binds selected attempts and hashes. An evidence locator alone does not approve acceptance. Insufficient calibration can coexist with functional acceptance. |
| **E8 — Qualified performance observation** | The claimed metrics and responsiveness result are qualified for this exact tested configuration. | Complete correct workload and fidelity, valid CPU/GPU/resource records, applicable sufficient populations, actual applicable calibration pass, and separate responsiveness classification. Preserve measured values when a qualification gate fails. Completing all calibration controls does not pass calibration. |
| **E9 — Confirmed bounds** | The campaign establishes a tested bound of the stated kind and scope. | Frozen matching workload/runtime/inventory, the prescribed independent repetitions, append-only search history, actual achieved inventory, tested pass/fail points, unstable/non-monotonic points and remaining gaps. Ordinary endpoints need three matching outcomes. Explicit allocation failure permits at most one diagnostic retry and needs two matching observations for its special observed failure endpoint. |

E0–E7 expand functional evidence. E8 is an additional performance branch: failure there does not erase independently valid correctness or functional acceptance. E9 keeps interactive, time-budget and observed-capacity bounds separate. An interactive bound requires the applicable E8 gates; correctly completed capacity evidence can remain valid with unqualified performance. A confirmed tested bound is conditional on its workload and host, not a universal architectural maximum.

## Gate details and existing commands

### E0–E2: foundation and admission

Run from the repository root. Read `bend guide` before using Bend. `make test` includes the safe proof gate, eight Bend runtime suites, native geometry fixtures and the Python reference/report/supervision tests; it does not replace the real Vulkan matrix.

```sh
bend guide
make test
make proof-verdict
```

Retain exact commands, exits and logs. Before committing, require `bend PROOF.bend` and its supported verdict mode. Keep contracts in `LAWS.bend`; the ladder adds no new formal theorem about `@unsafe` geometry or foreign Vulkan code.

Use [the admission recipe](../features/megascene-admission.md) for the public CLI and artifact checks. Implementation acceptance requires admission on small/large with both seeds 45/46. Its primary Vulkan matrix uses seed 45; seed 46 is an independent content diagnostic, not statistical coverage.

### E3–E5: real scenes and complete behaviors

Use [rendering/traversal](../features/megascene-rendering.md), [picking/destruction](../features/megascene-editing.md) and [evidence/review](../features/megascene-evidence.md). The public runner owns validation, frozen input, capture and supervisor boundaries; do not duplicate them in a second harness.

| Complete case | Required observable invariant |
| --- | --- |
| `static-v1` | Opening world and per-body geometry remain unchanged; actual native meshes and shadows obey the declared cache rules. |
| `traversal-v2` | All twelve route phases and review views occur; camera/culling changes preserve world geometry and reuse unchanged full meshes. Route versions have separate validation identities. |
| `picking-v2` | Every enabled hold ray reaches its independently declared owner/material/face, disabled frames remain disabled, overlays change without editing the world. |
| `localized-v1` | The single accepted cut removes exactly 16 concrete cells, preserves protected material and unaffected owners/caches, and has the required identity/mesh/shadow transition. |
| `support-v1` | All six cuts are accepted, protected footings survive, all three released spans actually move through ordinals 31–42, and component IDs/motion/cache checks agree. |
| `history-v1` | All 120 accepted cuts, overlaps/revisits, release and moved-beam target occur with the required intermediate action/state/geometry checkpoints. |

Only static admits explicit short primary smoke prefixes. Primary traversal, picking, localized, support and history require the complete schedule. Their diagnostic variants have separate frozen identities and applicability rules.

`state_correctness`, `rendering_correctness`, `visual_quality`, `numeric_validity` and `schedule_completion` remain separate. A full positive case requires the applicable dimensions to pass; a deliberate negative fixture passes by producing its declared failure, not by pretending the positive case completed.

### E6–E7: wider scope and implementation acceptance

Use [checkpoint/thread comparisons](../../../../docs/megascene-validation.md), [reproduction](../../../../docs/megascene-reproduction.md), and the [minimum acceptance checklist](../../../../docs/megascene-spec.md#minimum-implementation-acceptance-coverage).

The 45 positive configurations comprise:

- 18 small primary configurations: six cases at 1080p, each at 1/6/12 threads.
- Six large primary configurations: all six cases at 1080p and six threads.
- Two small 360p diagnostics: static/history at six threads.
- Eight paired full/proxy configurations: traversal/picking on mixed-world and compact-reference routes at small/1080p/six threads.
- Eleven prescribed diagnostic controls, including material/surface/terrain/body controls and the accepted cut/span variants.

Small static/history need three eligible timed observations per thread configuration, including the initial observation when eligible. The reviewed record consequently selects 57 timed attempts across 45 configurations. Those repeats must match runtime/input/schedule/instrumentation identities; three arbitrary passes are insufficient.

Independent references, both-seed admission, negative handling, search/persistence tests, archived reproduction and unchanged Light Atelier behavior are additional checklist obligations. The 72-control calibration matrix must execute faithfully and retain honest outcomes. Its actual passing status is an additional requirement for affected performance claims, not a prerequisite for a truthful functional acceptance decision.

Use [the acceptance record](../../../../docs/validation/megascene-acceptance/README.md) and its separate [reviewed decision](../../../../docs/validation/megascene-acceptance/acceptance.json). `index.json` is a locator and intentionally remains `unassessed`; reading it as a verdict would lose the decision's selected identities and reviewed scope.

### E8: calibration, populations and responsiveness

The [report reader](../../../../docs/megascene-report.md) and [calibration protocol](../../../../docs/megascene-calibration-controls.md) define the exact gates:

- An ordinary population needs at least 1000 ordinary frames **and** ten measured seconds in one attempt. Startup, warm-up, flush and teardown do not supply those seconds.
- An applicable edit-percentile gate needs at least 100 accepted edits in that attempt. Localized's one cut and support's six cuts remain insufficient; do not borrow history's edits or pool repeated attempts.
- Prescribed calibration covers static/history × small/large × 1/6/12 threads at full 1080p: 12 configurations, six fresh controls each, in `off/on/on/off/off/on` order.
- Both modes need complete separate validation and matching application bytes/workload/scope. Off retains the common recorder, resources, allocations, initial/final state and scalar outcomes. It cannot establish actual intermediate-state equality or count as a benchmark endpoint.
- Every applicable statistic needs sufficient controls and valid nonzero denominators. Above 5% off variation is `noisy`; otherwise any paired increase above 5% is `failed`. Only all applicable passing statistics qualify the exact tested configuration. Never subtract instrumentation cost.
- Ordinary CPU/GPU samples, startup, edit response and resource observations retain their actual intervals and units. CPU return/submission timing does not establish physical input-to-display latency.
- Recompute the public report and preserve separate population, calibration and responsiveness outcomes. Calibration on static/history does not automatically cover traversal, picking, localized/support, proxy, another resolution or an additional scale.

Use `python3 scripts/megascene_calibration_series.py plan` to inspect the exact plan without launching workloads. Launch or assess series using the documented commands and the established campaign; do not rerun the whole matrix merely because a series is already known to be insufficient.

Historical schedules admit at most 3600 measured frames and require 120/3600 for complete primary nonstatic cases. [Performance v2](../../../../docs/megascene-performance-v2.md) separately admits exactly two small/seed45/six-thread/full/1080p configurations with 120/21600 schedules, 21721 GPU query pairs and matching native/reader bounds. It requires ten seconds summed over disjoint ordinary-frame intervals in every control; motion/edit duration and the wall interval do not supply those seconds. Its history schedule explicitly records action density and the release-to-moving-target gap. Keep its results separate from acceptance #68. If a fixed schedule cannot supply qualifying duration, define a new bounded schedule identity and implement its admission/validation support. Do not extend a running attempt until its stopwatch reaches ten seconds, pace it artificially, silently relax the minimum, or classify existing insufficient controls as a pass.

### E9: bounded scale search

Follow [the bounded search workflow](../../../../docs/megascene-search.md). Inspect retained `search/search.jsonl`, `search/state.json` and per-configuration series before dispatching more work. `--dispatch-limit 1` bounds dispatch count, not the completeness requirements of the dispatched case.

Keep reserve stops, fragment-budget rejection, unsupported numerics, monitoring loss, deadline, device loss, crash and explicit allocation failure distinct. A signal alone does not establish physical exhaustion. Preserve non-monotonic and unstable results, attainable refinement points and untested gaps. The operational q=2..5 admission cap is not an observed hardware maximum.

## Current evidence, audited 2026-09-30

The [machine-readable audit](megascene-proof-status.json) records identities, counts, hashes and its limits. It checks retained evidence without launching new workloads or changing campaign ledgers.

| Evidence source | Current conclusion | Scope of this audit |
| --- | --- | --- |
| Reviewed issue #68 decision | **E7 functional acceptance: pass**, all 45 configurations, 57 selected timed attempts. | Rechecked decision-linked metadata and selected manifest/summary hashes; verified exact row settings, nonsynthetic identities, complete 120/3600 schedules, retained validation passes and the five functional/visual dimensions. Original raw runtime/capture bytes and visual judgments were not all revalidated in this audit. |
| Prescribed calibration | **E8 performance remains unqualified**; all 12 series are `insufficient`, although all 72 controls completed. | Rechecked each retained assessment/series hash. 45 controls are below ten seconds, including all 36 off controls; some on controls exceed ten seconds, which cannot qualify an insufficient pair. |
| This conversation's static run | **E3 smoke passed**, with a reviewed opening at small/seed45/six threads/full/1080p and one warm-up/two measured frames. | Separate validation, timing and capture; retained state/native/numeric checks, original capture hash, reviewer and cleanup. It does not add another complete acceptance configuration. |
| Scale endpoint discovery | **E9 not established by these records**; it remains outside issue #68. | No limit campaign was launched by this audit; functional acceptance and a short static observation do not locate an endpoint. |

The smoke's public report contains `qualified_capacity: pass` **for its declared prefix** after opening review. Keep that original outcome, but credit the run only to E3; it cannot meet E4's complete primary schedule, E7's matrix or E9's confirmed bound. Read the outcome's scope before promoting a claim.

The existing functional record belongs to its archived runtimes and host. The snapshot's checkout revision identifies where the audit was made; it does not retag every historical runtime as that checkout's current executable. After a production change, determine which exact scopes remain eligible and revalidate the affected ones.

## Execution and stopping rules

1. State the requested claim and exact scope; choose its target rung.
2. Audit existing bindings, validation identities, review and source/runtime bytes before deciding what is missing. Reuse only through the repo's supported artifact checks.
3. Read both the active runner-root ledger and the established shared acceptance allowance. The [shared ledger](../../../../docs/validation/megascene-acceptance/allowance.json) retains approved additions and prior roots/charges. Its completion balance is historical, not a new live allowance. The helper's doctor checks the per-root lease only.
4. Execute missing work sequentially through the public runners with fresh local outputs. A separate validation process must not preload the timed process's world or caches.
5. Retain each attempted outcome and its stopping reason, recompute reports from the durable archive, assess required features, and check cleanup/durability.
6. Report the reached scope, evidence links, unmet gates and next missing evidence. `inconclusive`, `insufficient`, absent or stale evidence cannot promote a claim; lower independently valid evidence remains useful.

No new root or output resets the accepted shared allowance. When further runtime work exceeds the declared remaining budget, preserve progress and obtain an explicit addition under the existing contract. Never drop a gate or declare full acceptance/performance merely to fit the budget.
