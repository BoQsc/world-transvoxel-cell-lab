# World Transvoxel Cell Lab Addon

The addon provides the `WtTransvoxelCellLab` editor node and the
`World Transvoxel Lab` dock.

## Scope

- Native `world-transvoxel` dependency only.
- Regular and transition cell inspection with exact backend buffers.
- Production chunk, same-LOD, and mixed-LOD validation.
- Terrain edit fixtures, dirty-region accounting, and before/after deltas.
- Repro storage, integration reduction, performance history, and committed
  standards.

## Ownership

`WtTransvoxelCellLab` owns editable scene state, scalar-field sampling, and
visual roots. Focused services under `lab/services` own contracts, mesh
analysis, cell corpora, chunk validation, edit validation, performance, repro
storage, integration import, standards execution, report construction, and
inspection presentation.

The addon must not implement an alternate Transvoxel mesher. Diagnostic APIs
needed from the backend belong in `world-transvoxel`; editor UI, fixtures,
reports, and standards belong here.

Enable:

```text
res://addons/world_transvoxel_cell_lab/plugin.cfg
```

Headless validation:

```text
res://tools/run_cell_lab_validation.gd
```

Structural smoke:

```text
res://addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd
```
