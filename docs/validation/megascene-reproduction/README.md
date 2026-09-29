# Archived Megascene reproduction evidence, 2026-09-29

Issue #63 was exercised on the Linux/X11 Ryzen 5 1600 and GeForce GTX 1660
host. The public runner restored two complete, previously archived attempts
into clean durable directories. It used the saved executables, linked and
application native libraries, shaders, generated source, generation inputs and
frozen schedules. Each recovery created a separate complete validation replay
and timed process. Artifact hashes were checked before execution and after
copying; source evidence hashes were rechecked before comparison.

| Case | Source attempt | Reproduced attempt | Measured frames | Canonical checkpoint frames | Result |
| --- | --- | --- | ---: | ---: | --- |
| Static `static-v1` | `e96dbbb0-e024-41ff-9181-d0b30a8a697b` | `ab8215b0-943e-40c2-b596-c2bee60c0755` | 3,600 | 3 | Pass |
| Localized `localized-v1` | `63a796d2-c06b-42f5-9f29-efeaa0ce3d36` | `6a2e0a2c-f441-4c06-9f52-5e3b9accd983` | 3,600 | 4 | Pass |

All four processes in each pair completed startup, 120 warm-up frames and
3,600 measured frames with 1920 × 1080 full geometry at six threads. The
localized source and reproduction each accepted exactly one cut at measured
frame zero. The initial inventory, canonical checkpoint payloads, per-body
geometry hashes and actual work inventories agree exactly. Each recovered
attempt's `reproduction_comparison.json` has zero failures. Its `summary.json`
reports passing schedule completion, state correctness and reproduction.
Elapsed times were recorded as observations and were not compared.

The durable attempt directories are:

```text
Static source:       /home/aivv/megascene-issue63-static-full-source/0bfc8f84-03c1-4513-a979-657c5aeaa897/a9f75138-6699-4723-bac7-d848c361a63b/e96dbbb0-e024-41ff-9181-d0b30a8a697b
Static reproduction: /home/aivv/megascene-issue63-static-full-reproduced/8fa05308-eadf-4ac9-9850-62aa8db90bcd/3d1db462-eb00-4c74-8577-8ccf21b7736e/ab8215b0-943e-40c2-b596-c2bee60c0755
Localized source:       /home/aivv/megascene-issue63-localized-source/7133c18d-03ff-4013-8bf5-948c2032051e/058cdcb6-82a3-494c-b0b3-7e45a29f9964/63a796d2-c06b-42f5-9f29-efeaa0ce3d36
Localized reproduction: /home/aivv/megascene-issue63-localized-reproduced/b2b8b5f1-5c17-43e2-9621-ba8add58842b/3d6f0af5-d57f-49de-930d-17296d37b65c/6a2e0a2c-f441-4c06-9f52-5e3b9accd983
```

The source and recovered static bundles each retain 98 runtime/input artifacts;
the localized bundles each retain 101. The recovered bundles additionally retain
the original hashed summary, validation, comparison, inventory and CPU stream
under `source_evidence/`. Their manifests identify source and new validation
attempts, current host information, loaded host library hashes and effective
renderer settings. The invocations record the actual executable, loader,
native library path, environment, process outcome and resource supervision.

Public runner tests retain separate failed attempts for missing or tampered
artifacts, changed configuration, retrieval failure and an interrupted archive
copy. The interrupted copy leaves its partial bytes intact; exclusive creation
rejects an overwrite at that identity. A synthetic checkpoint fixture verifies
field-level mismatch reporting. Earlier unsuccessful development archives remain
under `/home/aivv/megascene-issue63-reproduction*`; they are excluded from the
passing pair above.

The full `make test` run passed 126 tests (three optional integrations
skipped). The subsequent focused recovery run passed all five tests after
adding the saved runtime-configuration guard. `bend PROOF.bend` and
`bend PROOF.bend --verdict` each reported
`ALL PROOFS CHECK`. The archived manifests, validation identities, selected
raw evidence hashes and read-only report classifications were rechecked after
the complete runs.

This is correctness and recoverability evidence for issue #63. It does not
qualify interactive performance, capacity, calibration or parent issue #47's
full matrix. Hash agreement and native observations are runtime evidence, not
formal proofs of unsafe or foreign code. The host Vulkan driver, kernel and
display remain platform dependencies; no cross-platform tolerance is implied.
