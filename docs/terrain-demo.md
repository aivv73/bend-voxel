# SVO terrain demo

The default application explores deterministic terrain. It replaces the table scene; terrain carving, connectivity, detached bodies, and physics are not part of this demo.

## Storage

`src/terrain.bend` stores a 32 × 32 × 32 domain in a five-level sparse voxel octree. Each cell is 20 cm wide. World coordinates span x/z = -3.2 to 3.2 meters and y = 0 to 6.4 meters. A leaf contains a uniform material ID, including zero for air. A branch has eight children, ordered by x + 2y + 4z. Equal leaf siblings collapse into one leaf, so empty and uniform solid regions have no descendant nodes. This is a pointer-style tree, not a packed child-mask representation.

A deterministic height function produces rolling hills with grass or stone at the surface and earth below. Generation builds and then collapses the tree without allocating a dense voxel array. It visits all cells during construction; this is a bounded prototype, not a large-world streaming generator.

The initial tree has 4,217 nodes representing 10,139 occupied cells. A fully expanded five-level octree would contain 37,449 nodes. These are logical node counts, not measured byte usage.

## Rendering and controls

Surface extraction walks occupied leaves and tests neighboring cells through SVO lookup. Out-of-domain neighbors are air. The resulting 4,452 exposed unit faces are cached once at startup. The retained SVO is the authoritative terrain representation; the face list is derived data.

The existing Bend3D rasterizer draws the cached faces with directional shading, back-face rejection, and near-plane clipping. Rendering does not perform octree ray traversal or empty-space ray skipping. Greedy meshing, view-dependent level of detail, and streaming are not implemented.

WASD and QE provide bounded free flight, with right-drag to look. R and the RESET button restore the terrain camera. Escape releases controls; clicking resumes them. There is no camera collision or terrain editing. The HUD reports solid cells, SVO node count, and the preceding frame duration.

## Verification

`make test` includes `tests/terrain.bend`, which checks all 32,768 cell lookups against the terrain generator, boundary behavior, uniform-node collapse, mixed-node retention, and total occupied volume. Every cached face must separate solid material from air, and the total face count must match an independent height-column oracle.

A CPU-rendered frame is shown in the README. No terrain frame-rate acceptance target has been measured. Historical destruction benchmarks and snapshots explicitly remain on `src/table-demo.bend`.
