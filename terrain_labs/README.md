# Terrain Lab Scenes

This directory will contain controlled Godot scenes and fixtures for specified
Terrain Qualification Program milestones.

Planned domains:

- edit semantics and construction;
- material and surface behavior;
- resolution and LOD behavior;
- large-terrain systems;
- structural destruction and stability;
- CPU/GPU differential qualification;
- performance and soak testing.

No domain scene is created merely because it appears in the program roadmap.
A domain begins when its milestone contract advances from `proposed` to
`specified`.

Terrain Lab scenes may depend on `world_transvoxel_terrain_lab` and the pinned
production dependencies declared by their milestone. They must not depend on
`world_transvoxel_cell_lab`.
