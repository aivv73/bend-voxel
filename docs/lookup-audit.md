# Lookup audit and one measured change

## Audit

The audit covered project-owned body/owner lookup, cell access, and picking paths.

| Path | Finding | Action |
| --- | --- | --- |
| `world.bend:body.find` | Recursive result was passed into `vec.choose` before selection. Head and tail hits had similar measured cost. | Replace the eager selector with a terminating recursive worker that carries the comparison result and returns the first matching vector. |
| `world.bend:remove.scan` | Looks up an owner for each of 19,200 cells, including air and protected material. Missing IDs remain a full-list search. | Leave unchanged; skipping ineligible cells is a separate candidate. |
| `world.bend:rebuild.one` | Looks up old motion once per rebuilt component to preserve offset and velocity. | Preserve behavior. |
| `demo.bend:replay.voxel` | Resolves a cell owner to its motion for moving/landed assertions. | Preserve behavior. |
| `world.bend` cell/flood/face accesses | Already use `Array.get` on the bounded lattice; no replacement index was needed for this experiment. | Leave unchanged. |
| `render.bend:ray.bodies` / `ray.faces` | Traverse candidates while accumulating the closest hit; a first-hit return would change picking semantics. | Leave unchanged. |

The only production behavior changed is how `body.find` searches. Its interface,
first-match behavior, vector fields, and zero-vector fallback remain intact.
The worker satisfies Bend's termination checker without adding `@unsafe`.
A closure-based delayed selector was tried locally and discarded after it
substantially increased late-hit and miss costs; it is not the measured final implementation.

## Measurement

Bend 2.0.25, AMD Ryzen 5 1600, CPU backend, one runtime thread. Both binaries
use the same `scripts/lookup-bench.bend`. Each case performs 19,200 lookups
against a shared list, checks the resulting checksum, and measures within the
process using the existing microsecond clock. Empty and single-body cases are
controls; other cases use 65 bodies (one anchor plus 64 fragments), with empty
face lists. This isolates lookup cost rather than representing a replay's owner
distribution or measuring disposal of an exclusively owned mesh.

One warm-up process per binary was excluded. Twenty measured rounds alternate
before/after and after/before order, serially. Case order inside each process is
fixed. These are medians of batch durations, not individual lookup latencies.

| Case | Before, µs | After, µs | Change |
| --- | ---: | ---: | ---: |
| Empty | 701 | 679.5 | −3.1% |
| Single body | 793 | 699.5 | −11.8% |
| Head | 6,164.5 | 732 | −88.1% |
| Middle | 5,960 | 2,626.5 | −55.9% |
| Tail | 5,803.5 | 4,420.5 | −23.8% |
| Missing | 5,821 | 3,945 | −32.2% |

[Raw lookup samples and hashes](validation/lookup-audit/report.json) retain every
measured sample. The comparison demonstrates lower lookup cost on this machine;
small differences in the controls should not be treated as established gains.

A separate 20-round alternating comparison ran the identical updated world
test suite against both production implementations, also with one excluded
warm-up per binary. Python `perf_counter_ns` measured whole-process time,
including startup, test assertions, and captured output. All output matched.
Median duration was **239.619 ms before and 243.854 ms after (+1.8%)**:
no whole-suite speedup was demonstrated. See the
[raw whole-world samples](validation/lookup-audit/world-report.json).
The machine was not isolated and clocks were not locked. Neither comparison
establishes FPS, cut-latency acceptance, or CUDA rendering gains; the windowed
acceptance benchmark was not run for this experiment.

## Reproduction and validation

Build the lookup harness against the baseline `src/world.bend`, save that binary,
then build against the changed source and run:

```sh
bend scripts/lookup-bench.bend -o build/lookup-before
# Apply the body.find change, then:
bend scripts/lookup-bench.bend -o build/lookup-after
python3 scripts/benchmark_lookups.py build/lookup-before build/lookup-after \
  --rounds 20 --output build/lookup-audit/report.json
make test
```

The recorded baseline revision and source/binary hashes are in the lookup report.
To repeat the world comparison, build `tests/world.bend` with each world source,
using the same current tests in both builds; run each with `--gpu off --threads 1`
in the same alternating order. Check stdout equality and retain all durations.

`make test` passed: world checks (including empty, missing, first duplicate,
and later-match field preservation), input/render checks, probe checks, and
10 Python tests. Existing world coverage includes moving-body inheritance,
landing, mesh area preservation, and fragment-cap rollback. `git diff --check`
also passed.
