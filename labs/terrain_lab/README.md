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

The Terrain Observatory scene renders a 3x3x2 native chunk window, diagnostic
triplanar materials, canonical dig and construction edits, chunk bounds, and
live native-mesh metrics. Native grid coordinates are presented at the
qualified 0.5 m sample scale, and both vertical layers needed by the dug
fixture are retained. It can apply sphere, capsule, and rounded-box edits
without depending on Cell Lab code.

`tools/run_edit_gate_b_validation.gd` executes the focused `TQP-09` through
`TQP-14` qualification. `tools/capture_edit_qualification_visual.gd`
regenerates the deterministic brush and temporal-edit cross-section reference.

`tools/run_wave_02_validation.gd` executes the focused TQP-18, TQP-19, and
TQP-20 first-batch evidence. `tools/capture_material_blending_visual.gd`
regenerates the deterministic four-panel material-blending reference used by
TQP-18 visual review.

`tools/run_wave_02_second_batch_validation.gd` executes focused TQP-21 and
TQP-22 evidence. The retained observatory image is captured twice on
Forward+/D3D12 and must be byte-identical before it can be reviewed.

Terrain Lab scenes may depend on `world_transvoxel_terrain_lab` and the pinned
production dependencies declared by their milestone. They must not depend on
`world_transvoxel_cell_lab`.
