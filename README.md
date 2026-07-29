# World Transvoxel Cell Lab Standalone

Standalone Godot project for the separate `world_transvoxel_cell_lab` editor
addon and its native `world_transvoxel` GDExtension dependency.

The implementation roadmap is tracked in `ROADMAP.md`.

## Lab Contract

The lab is intentionally cell-first. It exists to inspect and validate the
Transvoxel scalar-field unit that terrain is built from: regular cells,
transition cells, chunk composition, edit behavior, topology, and rebuild cost.

Terrain is the primary validation domain, but the primitive is not terrain-only.
The report keeps that distinction explicit: this is a Transvoxel cell preview
and validator for volumetric scalar-field surfaces, with terrain correctness and
performance as the main standard.

`world_transvoxel` is the implementation authority, not an infallible oracle. If
the lab proves a contradiction with topology checks, visual inspection,
reproducible cases, and focused tests, the expected outcome is an upstream
`world_transvoxel` correction rather than a lab-side workaround.

The integration game is a downstream proving ground, not the correctness
authority. It can reveal important terrain, streaming, edit, and rendering
issues, but those issues should be reduced into small lab repros before deciding
whether the fix belongs in `world_transvoxel`, the integration layer, or the
gameplay/runtime layer.

Open:

```text
C:\Users\Windows10_new\Documents\github_repositories\world-transvoxel-cell-lab\project.godot
```

The project enables only the lab editor plugin:

```text
res://addons/world_transvoxel_cell_lab/plugin.cfg
```

The native runtime dependency is loaded from:

```text
res://addons/world_transvoxel/world_transvoxel.gdextension
```

Use the `World Transvoxel Lab` dock in the editor, or press Play to run the
minimal preview scene. The lab requires `WorldTransvoxelCellProbe` from
`res://addons/world_transvoxel`; there is no local fallback mesher.

The default scene shows the editable regular-cell patch, a native
transition-cell probe, and a separate native LOD 0 production chunk probe
generated through `WtChunkMesher`. Each probe is labeled in 3D with its native
path and current triangle/sample counts.

The editor dock groups the current validation report by contract, regular
patch, transition cell, production chunk, baseline timing, and corpus results.
Use `Regular Corpus` to sweep all 256 regular cases, `Transition Corpus` to
sweep all 512 transition cases across 6 orientations, `Copy Report JSON` for
quick inspection data, or `Save Repro` to persist the current parameters, edits,
report, authority model, and integration-game classification policy under the
Godot `user://world_transvoxel_cell_lab/repros` folder. `Load Last Repro`
restores the latest saved snapshot onto the selected lab node.
