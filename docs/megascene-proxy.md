# Megascene proxy diagnostics

Issue #58 adds two separate routes to the existing Megascene runner. They do
not replace `traversal-v2` or `picking-v2`. Each route runs with `--profile full`
and `--profile proxy`, using the same frozen source world, 120 warm-up frames,
3,600 measured frames, binary32 cameras, physics and picking rays. Every
profile/case needs its own complete validation replay before a timed attempt.

| Diagnostic | Source | Measured holds | Picking |
| --- | --- | --- | --- |
| `mixed-world` | Unchanged small preset; central irregular owners 6, 11, 16 and 21 | 1,000 m, 100 m, 1,000 m; 1,200 frames each | The top-center ray is a declared miss at the far holds. It hits owner 20 at the near hold, so picking is explicitly disabled there. A changed far miss rejects admission. |
| `compact-reference` | Four disjoint copies of the irregular assembly at the annex's cell offsets and variations | Nine 120-frame holds at target render-pixel metrics 105, 75, 90, 105, 90, 75, 75, 75, 105; then hold 105 | Hold 6 aims at the nearest right-lobe face of owner 4. The independent source-face reference must confirm a reachable hit. Other holds use declared top-center misses. |

The mixed-world warm-up uses the same opening camera as primary traversal;
its far view begins at measured frame 0. The compact warm-up holds its 105-pixel
view to establish full geometry before the nine diagnostic holds.

The runner derives the native tile from each eligible body's actual bounds
center, with `floor((center_cells + 320) / 640)` on X and Z. It records the
actual member IDs, binary32 metric, selected IDs, aimed-at suppression, proxy
drawn IDs and the 80/100 entry/exit margins every frame. The compact reference
must follow `full/proxy/proxy/full/full/proxy/proxy/proxy/full` without an aim;
the picking variant becomes full at hold 6 while the hit is active and returns
to proxies at hold 7. Selection bookkeeping also runs in the full profile,
which always draws full body meshes in the main pass.

Use the normal runner with `--case traversal` or `--case picking`,
`--diagnostic mixed-world` or `--diagnostic compact-reference`, an explicit
`--profile full` or `--profile proxy`, `--preset small`, 1920x1080, and a durable
`--archive`. `--validation-only` retains the separate validation replay and
midpoint captures. A later timed run can reuse its exact validation with
`--validated ARCHIVED_BUNDLE`; `--runtime-from ARCHIVED_BUNDLE` can reuse compiled
bytes across the two profiles while running a new profile-specific validation.
All four compact profile/case combinations and both mixed-world profile/case
pairs are required for the accepted diagnostic matrix.

After both timed profiles finish, compare them with:

```text
python3 scripts/megascene_proxy.py --pair FULL_BUNDLE PROXY_BUNDLE --output proxy-pair.json
```

The pair report requires complete evidence, matching source and schedule bytes,
matching world/geometry checkpoints and picking outcomes, and unchanged shadow
fit and shadow work. It reports midpoint full-body and proxy draws, selected
and proxied members, retained full/proxy vertices, native CPU vertex-arena
capacity, uploads, rebuilds and full-mesh shadow draws. The Vulkan allocation
ledger remains in each bundle. Validation captures are bound to every hold
midpoint and completion; feature review remains explicit.
The shadow count separates the resident full-mesh draw list from draws issued
when the cached shadow map refreshes. Native CPU arena capacity, explicit
Vulkan allocation peak and process-tree RSS have different storage scopes.

Box proxies may change silhouettes, material boundaries and surface detail in
the main pass. A lower draw count does not imply equal visual fidelity or a
smaller resident world. Reports remain unqualified development observations
until applicable instrumentation calibration supports a performance claim.
All selection, picking, cache and shadow checks here are runtime/reference
evidence over native and unsafe code, not formal proofs.

The [retained issue #58 evidence](validation/megascene-proxy/README.md) records
all four completed pairs and their midpoint captures.
