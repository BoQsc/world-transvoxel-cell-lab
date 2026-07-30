# Terrain Lab Scenes

This directory contains controlled Godot scenes, tools, and retained evidence
for Terrain Qualification Program milestones.

Implemented reference domains:

- edit semantics and construction;
- material and surface behavior;
- resolution and LOD behavior;
- large-terrain systems;
- structural destruction and stability;
- CPU/GPU differential qualification;
- performance and soak testing.

The Terrain Observatory scene renders a 3x3 native chunk window, diagnostic
triplanar materials, canonical dig and construction edits, chunk bounds, and
live native-mesh metrics. It can apply sphere, capsule, and rounded-box edits
without depending on Cell Lab code.

Terrain Lab scenes may depend on `world_transvoxel_terrain_lab` and the pinned
production dependencies declared by their milestone. They must not depend on
`world_transvoxel_cell_lab`.
