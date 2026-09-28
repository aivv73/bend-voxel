# Megascene recipe planning checks

This is a small reference probe supporting the accepted
[workload recipe](../../megascene-workload.md), not the production generator or
stress suite. It imports no Bend world implementation and performs no Vulkan run.

Run with Python 3 and NumPy available:

```sh
python3 docs/validation/megascene-spec/recipe_audit.py
```

[Retained output](recipe-audit.json) covers all four neighborhood variations,
initial box disjointness and per-owner positive-face connectivity/anchors,
localized removal, dense support-component checks, the specified 120-cut history
occupancy targets for both presets/seeds, and the binary32 fall recurrence at
every frame of the specified 31..42 moving window.

The history probe evaluates moved-beam removal in its known local coordinates.
It does not reproduce the full moving world's state, IDs, checkpoints, surfaces
or caches. The fall probe checks the pre-contact interval where floor clamping
is inactive. Global numeric conversions, diagnostic variants, ray picking,
camera visibility, rendering, shadows, proxy selection and timing/resource
measurement are not qualified by this probe. Production acceptance must supply
the independent/scalable checks and real Vulkan evidence required by the handoff.

The output consists of recipe/reference expectations, not observed Megascene
performance, a measured scale limit, or a formal proof of unsafe/native code.
