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
`MEGASCENE_CACHE_ROOT` selects an absolute writable cache root for the current
process and inherited generator subprocesses. Otherwise an absolute
`XDG_CACHE_HOME` selects `$XDG_CACHE_HOME/bend-voxel`; existing checkout and
home cache defaults remain unchanged when neither is configured. Relative
`MEGASCENE_CACHE_ROOT` is rejected; relative `XDG_CACHE_HOME` is ignored.
Cache configuration does not change retained source bytes or worker identities.

Checkpoint and review table serialization now runs in `schedule_points.bend`.
It validates bounded frame/name counts and canonical names, rejects duplicate
names, and sorts by frame while preserving the order of coincident entries.
The Python schedule adapter only transports typed fields and returned bytes;
`megascene_checkpoint_plan.py` has been removed. Aggregate schedule parity also
checks these tables against the retained pre-migration byte hashes for all 84
configurations in `megascene_runtime_artifact_bits.json`. Those hashes were
captured from main `957c84b` before replacing any runtime serializer; the fixture
also retains camera, ray, policy and supplementary hashes.

Camera, picking ray, frame policy and supplementary tables now use
`schedule_binary.bend`. Bend checks row boundaries and completeness, bounds,
canonical numeric words and unique supplementary frames before opening the
output. It writes little-endian bytes through the existing Base file effects;
there is no new C/C++ dependency. The Python adapters transport fields and read
the completed file, preserving the public helper APIs. Python packing loops for
these tables, including the runtime identity comparison, have been removed.
Aggregate parity checks every retained runtime artifact hash for all 84 cases.
The formal claims cover the two stated word literals and startup tie ordering;
complete byte parity, file IO and native readers are runtime/reference checks.
Use `python3 -B` to inspect retained Python helpers without creating bytecode files.

`tests/schedule-points.bend` and `tests/schedule-binary.bend` now own the bounded
serializer and native reader checks. Their literals, damaged-input cases, complete
output checks and maximum-count fixtures replace the Python native-reader suites.
The aggregate invokes them through `test_schedule_contracts.sh`, using one owned
temporary directory and bounded Base process effects. Python retains the archive
identity and field-adapter checks until those callers migrate.

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
