# Megascene computation in Bend

Megascene callers now obtain district sources from Bend. The admission and replay
commands keep their existing options, source records, owner IDs, and frozen inputs.

`src/megascene_recipe.bend` owns terrain, buildings, spans, irregular assemblies,
seed variation, row-major ownership, and all five terrain controls. It uses typed
control and district records and produces ordered cuboids without calling unsafe
geometry code. `src/megascene_source.bend` validates the requested scale and seed,
then emits a complete source stream. The Python adapter verifies the header,
control, owner order, neighborhoods, and integer transport before the existing
independent source-admission checks run.

`src/megascene_scale.bend` owns squared-area growth, midpoint refinement, coprime
history stride, and prior-visit counting. Binary integers preserve arithmetic
beyond U32 and Base's decimal `Nat.read` range. Python converts decimal transport
in bounded chunks without changing the interpreter's global conversion limit.
Worker execution still has a 60-second timeout. The supported district envelope
remains q=2..5.

`scripts/megascene_bend.py` builds native workers from frozen dependency bytes.
The cache key includes their source bytes and the pinned Bend version. Result
caching uses that key, so editing Bend dependencies invalidates previous results.
The adapter decodes fresh owner objects on every call. File locking and atomic
publication prevent concurrent callers from observing a partial executable.

Admission and fresh replay archives retain the generator dependencies. Runtime
reuse retains a separate complete `runtime/generator` directory for refreshed
reference tools, including when the original archive predates this migration.
The archived renderer sources and executable bytes remain available unchanged.
Running retained helpers stores their build cache outside the archive.
Use `python3 -B` to inspect retained Python helpers without creating bytecode files.

Python continues to freeze camera, ray, and action schedules, manage processes and
archives, and perform independent occupancy, surface, picking, edit, and motion
checks. Generated replay entries still contain the admitted frozen cuboids.
Generation therefore stays outside measured startup and before unsafe construction.
The migration adds no parallel calls or performance claims.

## Verification

`tests/fixtures/megascene_recipe_baseline.json` records exact ordered source hashes
captured before the port. `tests/test_megascene_bend.py` checks all 48 combinations
of four scales, two seeds, and six recipe modes. It also checks malformed and
incomplete transport, source-cache invalidation, old archive dependencies, mutable
result isolation, and identical source order at 1, 6, and 12 threads.

`tests/test_megascene_scale.py` compares policy results against independent integer
references, including 100-digit inputs and actual history schedules. Six new laws
in `LAWS.bend` cover district acceptance, half-after-double, exhausted search fuel,
empty prior visits, and a lower midpoint tie. Both `bend PROOF.bend` and
`bend PROOF.bend --verdict` pass. These laws do not prove unsafe geometry or native
rendering properties.

Short real Vulkan static replays at 1, 6, and 12 threads passed state, geometry,
numeric, and declared-schedule checks. Their canonical checkpoints and actual
geometry work matched exactly. These two-frame observations do not establish
performance or completion of the full 120/3600 schedule.

Run `make test` and `make proof-verdict` to repeat the repository checks.
The [verification record](validation/bend-migration/verification.json) retains
the 181-test result, proof verdicts, and Vulkan checkpoint hashes.
The [decision trail](validation/bend-migration/decisions.tsv) records migration
choices and the reference checks used to verify them.
