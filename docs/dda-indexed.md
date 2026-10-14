# Indexed compressed-tree experiment

The indexed prototype was rejected. CPU12 complete-frame medians rise from 102.28125 ms to 397.6875 ms, with all five paired processes slower. The accepted renderer remains installed, including redundant-floor removal and boundary-count reuse. The [candidate](dda-indexed-data/candidate-dda.bend), [patch](dda-indexed-data/candidate.patch), proofs, and executable properties are retained for review and reproduction.

## Storage and ownership

The installed Bend 2.0.34 runtime treats native arrays as affine owners. Its shared `Array.fork` and `Array.join` definitions are unsafe; the checked shared-array example fails ordinary proof checking. The [ownership investigation](dda-indexed-data/grounding.md) rules out those handles for this candidate. Copying the proposed 32 MiB native table into 4,096 render leaves would require 128 GiB; those are calculated sizes, not measured allocations.

An [independent judge](dda-indexed-data/design-judge.md) selected spatial pages from three designs. The implemented reusable `Data` index groups four binary spatial splits and their frontier into 31 fixed rows. A balanced directory resolves scalar `Nat` page addresses. Rows distinguish materials, local splits, page links, and padding. Child slots are derived. Every U32 material remains a separate payload; page addresses and directory cuts have no added U32 ceiling. The index is a collection of immutable pages, rather than one contiguous native array.

Packing consumes the result of the existing construction tree. The runtime grid contains one query representation. Public `Grid.build`, `Grid.read`, and `Grid.region` call shapes remain unchanged, as do Trace, Frame, fork-six and fork-seven decomposition, paint precedence, compression, and the complete arithmetic suffix. The actual Atelier tree has [1,397,085 nodes, 698,543 leaves, and depth 27](dda-indexed-data/tree-size.txt). Four-split packing creates [99,794 pages](dda-indexed-data/page-count.txt).

The compiled row selector uses a [jump table and two selected word loads](dda-indexed-data/page-row-assembly.txt). Native lookup code uses borrowed page and directory access. It does not transport all 62 page fields through the getter's interface. Directory lookup restarts at each page transition, and local row selection still makes a helper call. These are plausible contributors to the regression; their individual costs have not been isolated.

## Correctness and its limits

The candidate's [LAWS](dda-indexed-data/LAWS.bend) and [PROOF](dda-indexed-data/PROOF.bend) add twenty component laws. They cover row order, padding, valid child slots, directory routing, spatial steps, link state and fuel reduction, height bounds, outside sentinels, and full Region equality for solid and single-split trees across arbitrary U32 materials. Both [ordinary checking](dda-indexed-data/proof-check.txt) and [kernel checking](dda-indexed-data/proof-verdict.txt) pass. The published snapshots also pass [ordinary checking](dda-indexed-data/published-proof-check.txt).

Universal packing equivalence for arbitrary trees, general link validity and acyclicity, and sufficient fuel with unreachable padding remain unproved. Component proofs and the finite executions below do not establish those universal claims. Invalid or exhausted internal paths return the empty sentinel in this experimental implementation.

The [structural observer](dda-indexed-data/topology-property.bend) follows addresses in the actual packed table and matches both child routes against the frozen construction tree. It compares every material and checks link range, ordering, and node/link counts. [All 1,397,085 Atelier nodes and 99,793 links match](dda-indexed-data/topology-run.txt). Empty, uniform, dense, overlapping-cuboid, and generated terminal-depth-zero-through-twelve worlds also match. This observer reads the representation; production query routing is checked independently.

The [region property](dda-indexed-data/world-property.bend) calls both actual `Grid.build`, `Grid.read`, and `Grid.region` implementations. It compares materials and all six bound coordinates. [All 10,478,145 Atelier probes match](dda-indexed-data/property-run.txt): eight corners, the centre, and six face centres of every frozen compressed leaf. Narrow leaves create repeated coordinates. Every cell of the small worlds is also checked, including effective clearing, high-bit and maximum U32 materials, outside coordinates, and page-boundary depths. This is a finite sweep, not exhaustive Atelier-cell coverage or a universal theorem.

Seven views compare region DDA with unit DDA. [All 1,835,008 rays match exact surfaces](dda-indexed-data/verification.txt), including depth, cell, face, and material. Opening, cut, cube, carved cube, inside, axis-aligned, and opposite image bytes match the frozen renderer and its unit reference on CPU12 and forced GPU fork six. Opening also matches on CPU1, CPU6, and GPU fork seven. [Parity records](dda-indexed-data/image-parity.txt) and [hashes](dda-indexed-data/image-hashes.txt) identify the exports. The actual native-window captures have [zero pixel differences](dda-indexed-data/window-parity.txt).

## Complete-frame measurements

The unchanged Bend A/B driver runs five process pairs in alternating AB/BA order. Each process warms four frames. The interval includes rendering, native X11 presentation, and image disposal; construction is excluded. Every process must exit successfully and report its requested frame count. Release timing does not overlap builds, proofs, profiling, property execution, or image checks. Load records retain the shared desktop environment. The development machine has a Ryzen 5 1600 and GTX 1660.

A [same-binary control](dda-indexed-data/aa-control.tsv) gives medians of 103.28125 and 104 ms. Its difference is about 0.7 percent. The CPU12 storage regression is much larger. Its accepted process means range from 101.625 to 104.75 ms, while candidate means range from 396.46875 to 398.46875 ms. A second positive-gain batch was not run because the initial performance gate failed.

Opening-view complete-frame results are milliseconds per frame. Each median summarizes five process means; ranges retain the slowest and fastest process means.

| Execution | Measured frames per process | Accepted median (range) | Indexed median (range) | Evidence |
| --- | ---: | ---: | ---: | --- |
| CPU12, fork six | 32 | 102.28125 (101.625–104.75) | 397.6875 (396.46875–398.46875) | [Samples](dda-indexed-data/cpu12.tsv) |
| CPU6, fork six | 16 | 139.8125 (132.1875–141) | 516.5 (512.5625–521.6875) | [Samples](dda-indexed-data/cpu6.tsv) |
| CPU1, sequential | 8 | 673.625 (670.375–676.375) | 2761 (2752.25–2770.5) | [Samples](dda-indexed-data/cpu1.tsv) |
| GPU, fork six | 8 | 528.625 (501.375–543.5) | 4064.875 (3944.125–4198.75) | [Samples](dda-indexed-data/gpu6.tsv) |
| GPU, fork seven | 8 | 506.375 (501.875–514.75) | 3899 (3790.375–3949) | [Samples](dda-indexed-data/gpu7.tsv) |

Every paired candidate process is slower in these batches. Both GPU decompositions were measured directly. CPU thread scaling was not used to predict GPU behavior. These results reject this safe paged implementation; they do not rule out every possible indexed layout or a future safe immutable native-array API.

An additional CPU12 batch with 64 measured frames repeated the opening scene: accepted median 104.375 ms (103.03125–105.4375), indexed median 403.015625 ms (398.921875–409.125). Its original carved label was incorrect because the invocation omitted `--cube --cut`. The [raw samples](dda-indexed-data/opening-cpu12-64.tsv) are preserved under the correct label. The corrected carved comparison is reported separately. Each comparison's stdout and load records are retained alongside its TSV.

The corrected [carved-cube comparison](dda-indexed-data/carved-cpu12.tsv), using CPU12, fork six, and 64 measured frames per process, gives accepted median 17.0625 ms (16.890625–17.265625) and indexed median 17.6875 ms (17.53125–17.859375). All five pairs favor the accepted renderer in this batch. The regression is much smaller here than in Atelier. [Completion records](dda-indexed-data/measurement-completion.txt) cover all 80 processes, including the relabeled opening repeat and same-binary control.

## Reproduction and artifacts

The full release executables, GPU companions, emitted C, images, source copies, load records, and canonical decision trail remain in `.audit/dda-indexed/`. [Build hashes](dda-indexed-data/build-hashes.txt) identify the measured candidate. Published snapshots change only imports to use the unchanged shared engine modules; [source comparisons](dda-indexed-data/published-source-parity.txt) check the remaining text byte for byte. The accepted engine, proof files, and renderer binaries still match their [frozen hashes](dda-indexed-data/retained-hash-check.txt).

The published structural and region drivers were rebuilt and executed through the reproduction paths below. Their [topology output](dda-indexed-data/published-topology-run.txt) and [region output](dda-indexed-data/published-property-run.txt) match the original executions byte for byte. The retained root [PROOF also checks](dda-indexed-data/retained-proof-check.txt).

```sh
bend docs/dda-indexed-data/PROOF.bend
bend docs/dda-indexed-data/topology-property.bend -o build/dda-indexed-topology
build/dda-indexed-topology --gpu off --threads 1
bend docs/dda-indexed-data/world-property.bend -o build/dda-indexed-world
build/dda-indexed-world --gpu off --threads 1
CUDA_HOME=/opt/cuda bend .audit/dda-indexed/work/scripts/dda_compare.bend -o .audit/dda-indexed/candidate-renderer
bash .audit/dda-indexed/verify-images.sh
bash .audit/dda-indexed/run-matrix.sh cpu12-reproduction 12 off 6 32
```

Foundational Thinking required ownership and real tree sizes before storage selection. Model the Domain separated rows, addressing, and spatial state. Exhaust the Design Space compared three layouts and an independent judge. Type System Discipline kept reusable Data and Nat addresses, with proof scope explicit. Separate Before Serializing Shared State isolated the writer from the installed renderer. Build the Lever produced reusable Bend structural and region observers. Laziness Protocol preserved existing construction, callers, arithmetic, and render decomposition. Sequence Work into Verifiable Units placed correctness before measurements. Prove It Works required actual surfaces, exports, and native-window parity. Explain the Number required alternating complete-window measurements and rejected the slower prototype. Guard the Context Window kept large native output in evidence files.

## Attention

reviewed by gpt-6.1-sol

[Independent final review](dda-indexed-data/review.md): ALLOW. No flags. The reviewer reconciled all 80 process samples and the scene-label correction against the current task's transcript and canonical trail.

The [comment review](dda-indexed-data/comment-review.md) found no new comments or unenforced constraint comments. General arbitrary-tree packing proofs remain open; the candidate is experimental and is not installed. This checkout has no Git metadata, so delivery is local.
