# GPU decomposition and pixel assignment

The DDA comparison now supports a portable assignment sweep. On the measured GTX 1660, interleaved fork six reduces complete-window Atelier frame time by **10.9 percent and 11.6 percent** in two independent five-pair batches against a tuned contiguous control. It is an explicit option. Contiguous fork six remains the default because interleaving is slower on CPU and on the carved cube.

```sh
make build/dda-compare build/dda-sweep
build/dda-compare --gpu on --threads 1 -- --renderer dda --assignment interleaved --fork-depth 6 --bench 24
build/dda-sweep --gpu off --threads 1 -- sweep build/dda-compare build/dda-compare 1 on 8 build/dda-sweep.tsv opening
build/dda-sweep --gpu off --threads 1 -- pair build/dda-compare build/dda-compare 1 on 16 build/dda-pair.tsv opening contiguous 9 interleaved 6
```

The sweep measures contiguous and interleaved ownership at depths four through nine. Supported scene names are `opening`, `cut`, `cube`, `carved`, `inside`, `axis`, `opposite`, and `all`. A pair can select each endpoint's assignment and depth independently. Each result retains actual parsed options, process argv, stdout, stderr, exit status, completed frame counts, and all paired samples. The runner itself uses CPU execution; its endpoint arguments select CPU or GPU rendering.

## Measurements and retention

The opening-view matrix uses five alternating AB/BA process pairs per configuration, four warm frames, and eight measured frames per process. Construction and option reporting are excluded. The timed interval includes rendering, weave assembly, native X11 presentation, and image disposal. No builds, proofs, property execution, profiling, or image checks overlap release timing. The machine has a Ryzen 5 1600 and GTX 1660, with Bend 2.0.34. Desktop applications remain active.

These are medians of five process means in milliseconds per frame. The [full matrix](dda-gpu-data/opening-gpu.tsv) retains ranges, every sample, and the paired control for each row.

| Fork depth | Contiguous median | Interleaved median | Logical jobs | Pixels per job |
| --- | ---: | ---: | ---: | ---: |
| 4 | 2093 | 1437.25 | 256 | 1024 |
| 5 | 831.75 | 535.75 | 1024 | 256 |
| 6 | 508.75 | 456 | 4096 | 64 |
| 7 | 507.75 | 476.375 | 16384 | 16 |
| 8 | 507 | 472.75 | 65536 | 4 |
| 9 | 499.875 | 538.75 | 262144 | 1 |

Contiguous depths six through nine have overlapping ranges. The lowest observed contiguous median is at nine, so the independent confirmation uses that control rather than an untuned coarse depth. Logical job counts come from the algorithm. They are not physical GPU lane counts.

| Comparison | Measured frames per process | Contiguous median and range | Interleaved median and range | Evidence |
| --- | ---: | --- | --- | --- |
| GPU opening, tuned confirmation | 16 | 497.875, 494.0625 to 500.875 | 443.375, 440.5625 to 444.875 | [Samples](dda-gpu-data/tuned-gpu.tsv) |
| GPU opening, independent repeat | 16 | 506.375, 497.6875 to 510.6875 | 447.6875, 445.3125 to 447.8125 | [Samples](dda-gpu-data/tuned-gpu-repeat.tsv) |
| CPU1 opening, both fork six | 8 | 682.625, 673.625 to 689 | 786, 782.625 to 787.75 | [Samples](dda-gpu-data/cpu1.tsv) |
| CPU6 opening, both fork six | 16 | 135.6875, 135.375 to 145.125 | 159.3125, 158.8125 to 161.4375 | [Samples](dda-gpu-data/cpu6.tsv) |
| CPU12 opening, both fork six | 32 | 103.40625, 103.3125 to 103.75 | 111.90625, 111.09375 to 114.84375 | [Samples](dda-gpu-data/cpu12.tsv) |
| GPU carved cube, both fork six | 32 | 52.03125, 50.3125 to 52.6875 | 67.3125, 66.71875 to 67.53125 | [Samples](dda-gpu-data/carved-gpu.tsv) |

All ten tuned-confirmation pairs favor interleaving, with disjoint process-mean ranges. Every CPU and carved-cube pair favors contiguous ownership. These results support an opt-in setting for this large sparse scene on the current GPU. They do not establish a universal GPU default or Metal performance. No automatic scene heuristic is introduced.

A [same-binary GPU control](dda-gpu-data/aa-gpu7.tsv) has medians 498.25 and 509.125 ms with overlapping ranges. The reporting shell also matches the frozen renderer within measured variation on [GPU7](dda-gpu-data/noop-gpu7.tsv) and [CPU12](dda-gpu-data/noop-cpu12.tsv). Those legacy-format controls verify the shell's cost; they do not claim the frozen executable emitted the new option reports.

Separate diagnostics identify rendering as the main remaining cost. The three warmed control render stages measure 480, 517, and 475 ms; candidate stages measure 442, 437, and 444 ms. Presentation remains about 124 to 136 ms in those diagnostics. These stage timings are outside the release comparisons and are not additive bounds on their medians. [Device evidence](dda-gpu-data/gpu-attestation-filtered.txt) records the candidate CUDA process and sustained GPU activity. Interleaving still performs every pixel's traversal and shading, and adds assembly. More even job cost is a hypothesis for the gain, not an isolated causal measurement.

## Assignment and assembly

The scene owns one finite schedule. At depth `f`, `Q=2^f` and `S=512/Q`. A job has coordinates `qx,qy` below `Q`; its sequential local pixel has coordinates `ix,iy` below `S`.

| Assignment | Absolute pixel | Inverse ownership |
| --- | --- | --- |
| Contiguous | `qx*S+ix, qy*S+iy` | `x/S, y/S, x%S, y%S` |
| Interleaved | `ix*Q+qx, iy*Q+qy` | `x%Q, y%Q, x/Q, y/Q` |

Interleaving gives each job separated pixels across the image. Sequential weave at the existing joins moves each owner bit below the local-coordinate bits and restores canonical `Pix/Qua` placement. Leaves and weave contain no new parallel calls. Native Image remains the sole production result. At depths zero and nine, ownership coincides; helper overhead can still differ.

The [candidate snapshot](dda-gpu-data/candidate-dda.bend) preserves the original pixel expression, `Frame.seq`, `Frame.fork`, and all preceding DDA code. Grid storage, world construction, paint precedence, rays, traversal, palette, and shading remain fixed. The selected entry dispatches the same algorithm through Bend's execution model. No warp size, backend intrinsic, shared writable array, or backend-specific layout enters it. [Native region lookup](dda-gpu-data/region-code-review.txt) retains borrowed `term_peek` access without per-branch retain/drop operations.

Three designs considered sibling launch order, interleaved weave, and binary row batches. The [independent judge](dda-gpu-data/design-judge.md) selected interleaved ownership. The [selection](dda-gpu-data/selection.md) retains scalar hot arguments and report admission, and archives the row forest and its separate packing pass.

## Correctness and proof scope

The component [LAWS](dda-gpu-data/LAWS.bend) and [PROOF](dda-gpu-data/PROOF.bend) contain 69 proved claims. [Kernel checking passes](dda-gpu-data/proof-verdict.txt). They include 48 retained claims, 18 initial scheduling components, both general weave inverses under their original full-image premises, and a transpose recurrence. The two formerly open inverse identifiers retain their `_open` suffix; their proof bodies are present.

Eight exact general assignment and full-frame claims remain unproved in [open/LAWS.bend](dda-gpu-data/open/LAWS.bend). That specification reports eight TODOs and is not imported by the successful component proof module. Component checking is not a universal frame theorem.

The [native coordinate observer](dda-gpu-data/assignment-property.bend) calls production maps and inverses over all valid work addresses for both assignments and all ten supported depths. [All 5,242,880 addresses pass](dda-gpu-data/assignment-property-run.txt), with zero bounds, inverse, duplicate-owner, or missing-pixel failures. A sequential affine Array records occupancy in the observer. It is not a renderer buffer or a replacement renderer.

Seven frozen views also supply [1,835,008 exact surface comparisons](dda-gpu-data/reference-surfaces.txt). [Fifty-six exports](dda-gpu-data/image-parity.txt) and [sixteen selected-setting exports](dda-gpu-data/winner-image-parity.txt) match the frozen full images byte for byte. They cover CPU1, CPU6, CPU12, and forced current-GPU execution within the recorded configurations. Native-window captures have [zero differing pixels](dda-gpu-data/window-parity.txt). Ray verification bypasses assembly and remains supplementary evidence. Actual images do not cover every scene on every CPU count, GPU depths zero through three, or Metal execution.

The sweep derives labels and both endpoint argv from typed scenes. Each renderer reports its resolved options, and admission checks those reports before accepting completed frames. A real export caught argv0 entering the strict parser; both entry points now remove it. [Protocol review](dda-gpu-data/protocol-confirmation.md) also confirms the migrated benchmark CLI rejects eight missing valued options before rendering. [Renderer review](dda-gpu-data/renderer-review.md) found no correctness defect.

Final review found missing shared-helper prerequisites in the `dda-compare` Make rule. The rule now tracks all four helpers, and [Make's dependency query](dda-gpu-data/dependency-after.txt) confirms that editing any of them requests a renderer rebuild.

## Reproduction and evidence

The complete raw record is `.audit/dda-gpu/`. It includes every argv, stdout, stderr, exit, pair ledger, load capture, native/GPU executable, emitted C, source snapshot, and append-only decision trail. [Build hashes](dda-gpu-data/build-hashes.txt) identify measured artifacts. Published snapshots change import paths to share the unchanged engine modules.

[Completion evidence](dda-gpu-data/measurement-completion.txt) covers 200 admitted strict-runner processes, including the ten installed-tool functional checks, plus 30 legacy control processes. The installed GPU export matches the frozen image. [Installed proof checks](dda-gpu-data/installed-proof-exits.txt) pass ordinary and kernel verification. The [published coordinate observer](dda-gpu-data/published-parity.txt) was rebuilt and rerun with byte-identical output. [Installed hashes](dda-gpu-data/installed-hashes.txt) identify the retained code and binaries.

```sh
bend PROOF.bend
bend PROOF.bend --verdict
bend docs/dda-gpu-data/PROOF.bend
bend docs/dda-gpu-data/assignment-property.bend -o build/dda-assignment-property
build/dda-assignment-property --gpu off --threads 1
```

Model the Domain made scenes and schedules explicit. Type System Discipline kept depths finite and proof scope honest. Build the Lever produced the Bend sweep and exhaustive observer. Encode Lessons in Structure tied argv, reports, and labels to executed configuration. Explain the Number required tuned controls, independent GPU repeats, and CPU checks; it kept the default contiguous. Prove It Works required kernel checking, exact native exports, and a real window. Foundational Thinking and Exhaust the Design Space shaped ownership and the three competing layouts. Separate Before Serializing Shared State isolated writers and serialized heavy execution. Laziness Protocol retained the original pixel and contiguous paths. Sequence Work into Verifiable Units put parity before timing. Boundary Discipline and Fix Root Causes placed argument validation at the CLI entries. Guard the Context Window kept native source and bulk evidence in artifacts.

## Attention

reviewed by gpt-6.1-sol

[Independent final review](dda-gpu-data/review.md) allows the handoff with no unresolved defect. Eight general formal claims remain open. Metal execution and broader scene/configuration combinations remain unmeasured. This checkout has no Git metadata, so delivery is local.
