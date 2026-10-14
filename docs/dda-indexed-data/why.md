### The Question

What evidence constrains replacing the reusable compressed DDA tree with safe indexed storage? The strongest constraints are safe ownership, exact query equivalence, replication cost, and complete-frame performance. The original reason for declaring `Grid is Data` remains unknown.

### The Code in Question

The anchors are [Tree/Grid](/home/aivv/Документы/projects/bend-voxel-main/dda.bend:7), [lookup](/home/aivv/Документы/projects/bend-voxel-main/dda.bend:138), and [Trace/Frame](/home/aivv/Документы/projects/bend-voxel-main/dda.bend:339), plus [Scene and draw](/home/aivv/Документы/projects/bend-voxel-main/scripts/dda_compare.bend:10) and benchmark [Work](/home/aivv/Документы/projects/bend-voxel-main/scripts/dda_benchmark.bend:9).

### What We Found

- **[Direct]** The body remains the occupancy authority. The documented objection to dense columns concerns imposed terrain dimensions and material packing. Cuboid construction avoids allocating a dense 512³ array. [Body authority](/home/aivv/Документы/projects/bend-voxel-main/docs/design.md:3), [storage rationale](/home/aivv/Документы/projects/bend-voxel-main/docs/dda-optimization.md:17), [construction](/home/aivv/Документы/projects/bend-voxel-main/docs/dda-comparison.md:5).
- **[Supported]** Current reuse extends through recursive tracing, frame branches, retained scenes, and benchmark work. An ownership change therefore affects the consumer chain. These are observed mechanics, not original intent. [Trace](/home/aivv/Документы/projects/bend-voxel-main/dda.bend:368), [Frame](/home/aivv/Документы/projects/bend-voxel-main/dda.bend:436), [Scene.draw](/home/aivv/Документы/projects/bend-voxel-main/scripts/dda_compare.bend:45), [Work](/home/aivv/Документы/projects/bend-voxel-main/scripts/dda_benchmark.bend:9).
- **[Supported]** Installed native arrays remain affine with `Data` elements. Reads return the owner; cloning creates separate owners. Shared-handle `fork`/`join` are `@unsafe`, and the audit records ordinary proof failure. That check was not rerun here. [Array declaration](/home/aivv/.bend/bend2/base.bend:70), [get](/home/aivv/.bend/bend2/base.bend:2400), [clone and unsafe sharing](/home/aivv/.bend/bend2/base.bend:2294), [audit decision](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-indexed/decisions.tsv:4).
- **[Direct]** The rejected subtree-cache experiment reduced branch visits by 28.78%, yet CPU12 complete-frame medians increased from 111.75 to 243 ms across five alternating pairs. Ownership shape changed emitted borrowing; shared-root contention remained an inference. This establishes a measurement caution, not an indexed-storage verdict. [Recorded analysis](/home/aivv/Документы/projects/bend-voxel-main/docs/dda-cursor.md:35), [raw timings](/home/aivv/Документы/projects/bend-voxel-main/docs/dda-cursor-data/cpu12.tsv:2), [ownership trail](/home/aivv/Документы/projects/bend-voxel-main/docs/dda-cursor-data/decisions.tsv:5).
- **[Direct]** The recorded Atelier tree has 1,397,085 nodes, 698,543 leaves, and depth 27. Conditional on four-word records and power-of-two capacity, the audit estimates 32 MiB per table and 128 GiB for 4,096 replicas. These are conditional allocation estimates. [Count](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-indexed/tree-size.txt:1), [estimate](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-indexed/frame.md:13).

### What We Can Reasonably Infer

- **[Inferred]** Indexed storage of the existing compressed hierarchy appears compatible with the documented storage rationale. The rejection concerns a narrower terrain representation.
- **[Inferred]** Indexing alone is unlikely to settle safe sharing or performance. Affine ownership and the cache experiment suggest both require separate evidence.

### Competing Hypotheses

**[Speculative]** Indexed lookup may reduce query cost; ownership transfer or replication may consume those savings. The supplied evidence does not rank these outcomes for indexed storage.

### What We Don't Know

**[Unknown]** Local searches found no historical rationale for `Grid is Data`. Git metadata and a remote are absent, so commits, blame, and PR discussions cannot resolve it. Indexed-storage frame-time improvement and the precise contention cause also remain unestablished.

### Sources Consulted

- **Source control history:** Unavailable. The investigator searched local `docs` and `.audit` for reuse, affine ownership, indexing, arrays, grids, and sharing. This synthesis read all four supplied inputs and spot-checked citations.
- **Issue / ticket tracker:** Gap; no matching MCP available.
- **Long-form documents connector:** Gap; no matching MCP available. Local documents were examined through the source-control fallback.
- **Real-time team chat:** Gap; no matching MCP available.
- **Infrastructure observability:** Gap; no matching MCP available.
- **Error / exception tracking:** Gap; no matching MCP available.
- **Product analytics warehouse:** Gap; no matching MCP available.

### Confidence Summary

Confidence is high in the current ownership constraints and documented acceptance requirements. Original intent and indexed performance remain unknown. This pass was read-only, with no writes, Git mutations, delegates, or heavy checks.

### Preserve / Change / Avoid / Risk

| Constraint | Implementation requirement |
|---|---|
| Preserve | Every U32 material, paint order, exact compressed-leaf bounds and outside sentinel, observable geometry, and accepted floor-removal and boundary-count optimizations. [Required invariants](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-indexed/frame.md:5), [region behavior](/home/aivv/Документы/projects/bend-voxel-main/dda.bend:182). |
| Change | Ownership contracts may change throughout Grid, Trace, Frame, Scene, and Work. Establish full `Region` equivalence, valid indices/capacity, acyclicity, and termination. Existing region laws establish material equality only. [Law scope](/home/aivv/Документы/projects/bend-voxel-main/LAWS.bend:232), [grounding requirements](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-indexed/grounding.md:44). |
| Avoid | Unsafe shared array handles, replica explosion, narrowed material/terrain assumptions, geometry changes, backend dependencies, and traditional tests. Keep portable Bend, formal claims, and sequential leaves. [Project rules](/home/aivv/Документы/projects/bend-voxel-main/AGENTS.md:5). |
| Risk | Agreement between both DDA modes can hide a shared storage defect. Require independent baseline evidence and complete native frames at CPU1/6/12 and separate GPU depths 6/7, with matched settings, four warmups, five alternating pairs, and a second CPU12 batch. [Shared storage comparison](/home/aivv/Документы/projects/bend-voxel-main/scripts/dda_compare.bend:195), [measurement requirements](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-indexed/frame.md:7). |
