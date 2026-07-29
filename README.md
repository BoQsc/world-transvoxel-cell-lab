# World Transvoxel Cell Lab Standalone

Standalone Godot project for the separate `world_transvoxel_cell_lab` editor
addon and its native `world_transvoxel` GDExtension dependency.

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
