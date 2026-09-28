# Issue #50 verification

These are development observations and synthetic supervision tests, not
benchmark passes or capacity endpoints. Full validation/checkpoint, GPU timing
and calibration qualification remain separate work.

## Real static invocation

```sh
python3 scripts/megascene.py --case static --preset small --seed 45 \
  --threads 6 --resolution 1920x1080 \
  --output build/issue50-final-observation \
  --archive /home/aivv/megascene-issue50-evidence
```

The declared schedule completed: one startup, 120 warm-up and 3,600 measured
frames. All 3,721 frame references were retained and agreed with CPU records.
The explicit Vulkan allocation ledger peaked at 26,673,152 bytes and returned
to zero. There were no evidence errors or observed reserve crossings.

The supervisor retained 30 host/device samples and 27 worker heap samples.
Maximum observed coverage gaps, including launch/termination boundaries, were
100,082,156 ns for host/device monitoring and 358,453,368 ns for worker heaps.
Both remained within the one-second freshness limit. Process-tree RSS reached
an observed 123,904,000 bytes; available RAM and device free memory stayed above
their reserves. These are sampled observations, not physical memory ceilings.
The short measured duration does not establish responsiveness qualification.

[manifest.json](manifest.json), [summary.json](summary.json), and
[supervision.json](supervision.json) retain the configuration, exact observations
and retrieval information. Their relative evidence/artifact paths refer to the
full durable attempt archive, not this compact documentation directory:

`/home/aivv/megascene-issue50-evidence/b5f0a4ca-63ac-47df-b428-8645c793750e/4e43400d-d3c8-4cf9-b466-94144d8ef248/b90d27c9-b21c-4449-b3e9-f3368f301797`

That archive contains the actual runtime, frozen inputs, raw streams, shared
reference mapping and logs. No remote archive upload is implied. The original
7,200-second campaign allowance was retained. An accidental development
allowance entry was explicitly cancelled in the campaign ledger; it did not
fund an extension.

## Controlled failures and regression checks

[synthetic-results.json](synthetic-results.json) indexes 26 launched fixture
invocations and their archived summaries. The matching
[fixture test log](issue50-fixtures-verified.log) passed all assertions, including
reserve boundaries, monitor error/staleness/loss, startup/completion/case/campaign
deadlines, explicit allocation failure, device loss, crash, external interruption,
reference overflow/gaps/loss, malformed records and persistence failure.
The fixtures also cover frame/edit/action references, native allocation wrappers,
and campaign interruption/exhaustion with explicit additional allowance.

Synthetic fixture execution used temporary storage; completed evidence was
copied to `/home/aivv/megascene-issue50-evidence/synthetic-verified` for retention.
The production runner writes directly into its durable archive. An earlier
fixture run executed directly on the archive filesystem while other validation
was active. Filesystem stalls triggered valid monitoring stops before two
intended faults could execute. Those incomplete attempts remain in
[interfered-fixtures.json](interfered-fixtures.json) and the
[failed fixture log](issue50-fixtures-retained.log); they were not counted as
successful fault coverage or benchmark results.

The [real Vulkan integration log](issue50-integration.log) covers completion,
separate opening capture, artifact hash verification, relocation/replay of the
archived runtime, and controlled display failure. The
[runtime regression log](issue50-tests.log) includes all Bend runtime suites and
native geometry checks. The [Python regression log](issue50-python-final.log)
records 33 passing tests with the separately executed Vulkan integration skipped.
[Targeted supervisor tests](issue50-fixtures-last.log) passed again after
subsequent persistence changes.

Both [Bend proof](issue50-proof.log) and
[verdict](issue50-verdict.log) checks passed. Native/OS supervision, persistence,
allocation accounting and unsafe geometry remain runtime/reference evidence.
