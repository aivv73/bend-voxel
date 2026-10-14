**ISSUES.** One P2 finding in the migrated benchmark CLI. The new sweep admission path passed the scoped source and existing-artifact review.

- **P2: Missing valued options silently select defaults.** [dda_benchmark.bend:107](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/work/scripts/dda_benchmark.bend:107) and [line 112](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/work/scripts/dda_benchmark.bend:112) use `M.Options.flag` followed by `Maybe.default`. A trailing `--frames` selects 12 frames; a trailing `--assignment` selects contiguous assignment. The reconstructed configuration at line 114 never validates those original tokens. Thus `--label interleaved --assignment` can produce contiguous samples under an interleaved TSV label. This is a source-derived finding, not an executed reproduction. Reject missing values before selecting defaults. The strict sweep renderer path avoids this gap.

The following checks passed within this review:

- Parsed scenes own their schedules and actions. Renderer reports come from the resolved scene. Both strict renderer entry points remove `argv0` exactly once. The emitted runtime confirms that `IO.args` includes it.
- Each endpoint derives its own argv. Admission requires exit zero, exactly one matching option report, the requested host-thread count, and a matching completed-frame count. Explicit frame and thread counts must be positive.
- All ten carved records agree with their argv, report eight completed frames, have empty stderr, and record exit zero. TSV samples agree with the raw elapsed counts. File timestamps support the ledger’s AB/BA/AB/BA/AB ordering. See [admission-carved.tsv.pairs.tsv](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/admission-carved.tsv.pairs.tsv:1).
- Timing brackets selected rendering and assembly, `Window.frame`, and `Image.drop`. Initialization and four warm frames precede timing. Benchmark callers use the migrated scene-owned interfaces.
- Existing candidate and baseline window PNGs are byte-identical, with SHA-256 `0484d427cee5a04d660953d23daa65bb8f39ca00602eae15ed1004df539882c4`. I inspected both captures; I did not recreate them.

The evidence has these limits:

- [noop-gpu7.tsv](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/noop-gpu7.tsv:1) uses the legacy format. Its combined stdout lacks current option reports for the accepted endpoint and lacks the new per-endpoint argv/exit records. It does not establish current harness admission.
- `gpu_requested` accurately describes the request. The inspected candidate runtime has GPU calls and rejects an unusable GPU under forced `--gpu on`; the pending release matrix still needs its own execution evidence.
- No matrix result, repeatability conclusion, or performance improvement is claimed.

Method was **read-only source plus existing-artifact inspection**. No writes, delegation, git, builds, proofs, runtime, profiling, or traditional tests occurred.

Reviewed source hashes were checked twice and remained unchanged. Paths below are relative to `.audit/dda-gpu/`; the five Bend hashes match `source-hashes.txt`.

```text
b4f2ba8a004aa4d7c018c3141844c3d29ccf964321a0dd2d1c9714bb12dd7eac  work/scripts/dda_config.bend
de623eee773248fc8f81d01357032bc6ffed10dad3c4f3c6bc460e3dee22f0d8  work/scripts/dda_compare.bend
0ee634b23dcdb5b0be981257a76d75d24001e30db823cd10a511ae3308a18443  work/scripts/dda_benchmark.bend
fb6c7ec191dec1327a1c9e5595c9710282128d50754bb4c9358bacc9af04524b  work/scripts/dda_sweep.bend
8747d074739b687da6a1463b01c03a3ac1b23d7812fad07b8b2e7cd59bda8e2b  control.bend
ef01b15781f9a5490ac645f1e6f935557ab73201e5eabc6e2e9942d1869cca69  run-sweep.sh
b863f9edf16d39f9f18bf9752128e9cb6e8118daf6feaa86c050beb5d4971d8d  export-reference.sh
a55497bdfe8f0b48e0be5bff40174b5ba5f804c568e6a5772d1266a71b736d3d  screen-baseline.sh
bc9d0427df5856691173bfcb5c93ab6e48b95a07af6d57415d5dd35656c87367  verify-images.sh
```

Build identities were read from [build-hashes.txt](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/build-hashes.txt:1); binaries were not rehashed or executed.

Boundary Discipline focused the finding on CLI validation. Migrate Callers Then Delete Legacy APIs guided the caller inventory. Prove It Works kept the verdict tied to inspected artifacts.
