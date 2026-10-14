Recommend candidate 2 as the base, conditional on removing its address limit and confirming borrowed row access in emitted C. No package is ready for installation as written.

Read all six package files and the four grounding files end to end. Screened the supplied architectural red flags. Scores assess design readiness; no proofs, compilation, or performance checks were run.

| Criterion, 0–5 | Candidate 1 | Candidate 2 | Candidate 3 |
|---|---:|---:|---:|
| Exact material and full leaf bounds; no new limits | 3 | 3 | 3 |
| Safe ownership and proofs; unchanged CPU/GPU fork6/7 without replication | 3 | 4 | 4 |
| Indexed storage, scalar cursors, credible locality | 3 | 4 | 3 |
| Small interface, one installed representation, maintainability | 3 | 4 | 3 |
| Tractable laws and real-runtime equivalence strategy | 4 | 4 | 4 |
| **Total** | **16/25** | **19/25** | **17/25** |

All three preserve the accepted tree topology and reconstruct full bounds. All also introduce address ceilings. Candidate 1 uses U32 node IDs; candidate 2 uses U32 page IDs; candidate 3 explicitly rejects trees above `2^31` nodes. Full-U32 materials alone do not satisfy criterion 1.

Candidate 2 provides the clearest locality argument: a directory lookup selects a spatial microtree, then local slots cover up to four splits before another lookup. Candidates 1 and 3 group consecutive preorder records, so same-page traversal depends on the chosen path. Neither argument establishes faster frames.

The packages contain two structurally distinct storage designs. Candidates 1 and 3 share the preorder-page family. Candidate 2 changes page membership, local addressing, padding, and frontier transitions through spatial microtrees. Candidate 3 chiefly contributes a distinct traversal strategy.

Accept these grafts:

- Use candidate 3’s fused borrowed traversal. Resolve the page, traverse locally, and return only a region or scalar continuation. Candidate 2 already proposes this shape; candidate 3 makes its ownership and fuel requirements more explicit.
- Replace page IDs and page counts with `Nat`, including packing counters and directory routing. Converting back to U32 internally would restore the capacity limit. Avoid candidate 3’s whole-tree temporary array, whose capacity check remains restrictive.
- Derive local children as `2*slot+1` and `2*slot+2`. Prove that only interior slots contain splits. This removes redundant stored addresses and their consistency obligations.
- Use `RowSolid{material:U32}`, `RowSplit{}`, `RowLink{page:Nat}`, and `RowPad{}`. Adopt candidate 1’s compactness goal, while retaining explicit variants.
- Keep recursive boxed `Table` and select a row through borrowed `Page.row`. Confirm that emission loads the selected record without transporting every flattened page field.

I agree with the parent’s base preference. My qualification concerns the “two-word” graft: tag plus payload is a proposed layout, not established emitted behavior. `Nat` representation, row flattening, allocation classes, and borrowing still require confirmation. Reject candidate 1’s materialized wide-page cursor and sentinel encoding, and candidate 3’s capacity rejection.

The architectural screen finds three concerns. Candidate 2’s storage module and DDA wrapper must have one clear owner for packing invariants, avoiding pass-through layers and shared representation knowledge. Bend exposes constructors, so public opacity cannot replace validity predicates or erased witnesses. The alternative native-owner sketches must remain comparison material, rather than becoming another installed query path.

Open risks include directory contention, row-selection copies, Nat arithmetic, padding, and construction peak memory. The recorded node count and depth do not determine candidate 2’s page count; count its actual frontier distribution. No speed or memory improvement is established.

The implementation contract is:

1. Pack exactly the accepted construction tree. Preserve paint precedence, compression, every material, outside sentinel, crossing arithmetic, floor removal, and boundary-count reuse.
2. Prove packing succeeds without an added address ceiling, full `Region` equality, valid slots, unreachable padding, acyclic links, and sufficient decreasing fuel. Links preserve spatial state; splits advance it exactly once.
3. Install one indexed query representation. Retain reusable `Grid`, existing CPU/GPU fork6/7 decomposition, and sequential leaves, without table cloning.
4. Require ordinary and kernel proofs, emitted-C inspection, independent frozen-tree query checks, exact ray/image equality, strict GPU execution, and the supplied complete-frame measurement protocol before installation.
