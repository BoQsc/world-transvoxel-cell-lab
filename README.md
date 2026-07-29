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

The default scene also shows a native transition-cell probe in front of the
patch and reports its status in the overlay.
