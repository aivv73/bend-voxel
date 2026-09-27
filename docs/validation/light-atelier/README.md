# Light Atelier validation

Validated on 2026-09-27 using the local Vulkan/X11 desktop and Blender 5.2.2 LTS.

## Scene

The default world is a 44 × 34 meter courtyard containing a floor, backdrop, slatted canopy, and three Blender-voxelized sculptures. The opening camera is at `(9, 11, 25)` meters, with yaw `-2.8084` and pitch `-0.30` radians.

| Quantity | Initial value |
| --- | ---: |
| Occupied 10 cm cells | 803,970 |
| Anchored bodies | 6 |
| Sparse cuboids | 2,034 |
| Full-resolution surface rectangles | 10,341 |

These counts come from the compiled Bend world. The HUD's body counter reports detached fragments, so it starts at zero.

## Checks

The following commands passed:

```sh
make export-atelier-assets
make build
make test
make test-blender
```

The tests verify disjoint and connected exhibit geometry, protected anchors, the empty center and occupied rim of Oculus, reset behavior, camera aiming, plaster material handling in full meshes and LOD proxies, and mesh voxelization. Suzanne explicitly enables removal of isolated sample cells; the final export discarded one such cell.

## Visual inspection

- [Day, 1280 × 720](day.png): curved sculpture silhouettes and voxel steps are visible immediately. The canopy casts parallel stripes, Oculus casts an open elliptical shadow, and Twist casts a separate curved silhouette. Pale walls are free of the earlier diagonal self-shadow stripes.
- [Night, 1280 × 720](night.png): holding L reduces the sun contribution and exposes the cool ambient and warm camera work light. The work light does not cast shadows.
- [Default resolution, 640 × 360](default-640.png): all three exhibits, the cast shadows, and the controls remain readable.
- [Blender source preview](blender.png): the editable meshes rendered directly from `assets/light_atelier.blend`, before engine voxelization. Preview scenery and labels are excluded from export.

## Interactive edit and reset

A pointer cut on the right rim of Oculus removed 15 voxels, reducing the world to 803,955 cells. The [edited view](after-cut.png) has 49 changed pixels in the scene region compared with the day capture. Reset restored all 803,970 cells; the [reset view](reset.png) matches the pre-cut scene exactly in rows 150–614, excluding the HUD.

The [runtime trace](capture.log) records three shadow-map refreshes:

```text
vulkan shadow refresh bodies 6 rebuilt 6
vulkan shadow refresh bodies 6 rebuilt 1
vulkan shadow refresh bodies 6 rebuilt 1
```

These correspond to initial upload, the edit, and reset. The intervening day/night comparison and pointer motion did not rebuild the shadow map. This is a visual and behavior check, not a performance benchmark.
