# World Transvoxel Terrain Lab Addon

The Terrain Lab addon owns controlled experiments for the Terrain Qualification
Program. It is separate from `world_transvoxel_cell_lab` even though both addons
share this repository and the pinned `world_transvoxel` dependency.

Current status: program scaffold. All 46 TQP milestones remain `proposed`.

## Allowed Dependencies

- `world_transvoxel` is the current required native test dependency.
- `world_transvoxel_terrain` may become a pinned test dependency after a
  specified milestone requires production-layer comparison.

## Forbidden Dependencies

- Terrain Lab code must not preload, instantiate, or extend Cell Lab code.
- Cell Lab code must not preload, instantiate, or extend Terrain Lab code.
- Production projects must not depend on either lab addon at runtime.

The addon currently provides program metadata and boundary validation only. It
does not implement editing, materials, streaming, destruction, GPU meshing, or
other proposed terrain behavior.

Program document:

```text
res://docs/terrain_lab/TERRAIN_QUALIFICATION_PROGRAM.md
```

Boundary smoke:

```text
res://addons/world_transvoxel_terrain_lab/tests/wt_terrain_lab_smoke.gd
```
