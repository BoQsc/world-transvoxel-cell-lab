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
without depending on Cell Lab code. Every rebuild compares all adjacent native
same-LOD chunk boundaries and fails when any surface edge set or multiplicity
differs. This includes the retained smoothed-crater tangent regression from
`TQP-D011`.

The scene executes as an `@tool` preview in the Godot 3D editor. Selecting the
`TerrainObservatory` root exposes live Inspector controls for preview enable,
automatic rebuild, canonical edit seeding, chunk bounds, brush parameters,
dig, construction, reset, and explicit rebuild. Running the scene retains the
same terrain and exposes the larger on-screen interaction panel.

The TQP-32 Boundary Observatory is a separate `@tool` scene at
`scenes/boundary_enclosure_observatory.tscn`. It renders the retained closed
volume, capped terrain, and intentionally open contour through the native
chunk probe and exposes their chunk bounds and topology classifications. It is
an inspection surface for the boundary policy, not a production terrain scene
or a substitute for machine evidence.

The TQP-33 Independent Oracle Observatory is a separate `@tool` scene at
`scenes/independent_oracle_observatory.tscn`. It presents the clean native
closed assembly and representative missing, duplicate, flipped, and disconnected
defects while reporting the independent detector results. It is an oracle
inspection surface, not a fallback mesher or production terrain scene.

The TQP-34 Adversarial Corpus Observatory is a separate `@tool` scene at
`scenes/adversarial_corpus_observatory.tscn`. It exposes four retained seeded
generated cases, three fixed corrected regressions, all four completion-order
replays, and optional seed overrides while reporting the TQP-33 independent
oracle verdict. It does not simulate actual concurrent publication or widen
the retained corpus into a production terrain claim.

The TQP-35 Dynamic LOD Publication Observatory is a separate `@tool` scene at
`scenes/dynamic_lod_publication_observatory.tscn`. It runs the actual native
world-transvoxel runtime and exposes initial, split, merge, rapid supersession,
teleport, unload, and restart actions with live render/collision staging,
replacement, stale-result, coalescing, and transition-completion metrics.
Resident ownership bounds are diagnostic; the retained full frame trace, not
the settled screenshots, is authoritative for holes and overlap.

The TQP-36 Edit Invalidation Observatory is a separate `@tool` scene at
`scenes/edit_invalidation_observatory.tscn`. It applies the retained coarse,
fine, boundary, mixed-LOD, disjoint batch, no-op, and rapid-supersession native
transactions. Red lines show conservative edit bounds, yellow lines show the
independently expected padded dependents, and green lines show exactly changed
generations. Empty active payloads participate even when no render node exists.

The TQP-37 Adaptive Edit Observatory is a separate `@tool` scene at
`scenes/adaptive_edit_observatory.tscn`. It runs isolated native seam-carve,
corner-construction, repeated-tunnel, under-resolved coarse/refined, unloaded,
and reconstructive-history fixtures. It displays local triangle and native
edit-retention state alongside render and collision telemetry. Machine field,
topology, lifecycle, and temporal evidence remains authoritative; the scene's
48/64 collision profile and Windows debug timings are not production claims.

The TQP-40 Adaptive Streaming Observatory is a separate `@tool` scene at
`scenes/adaptive_streaming_observatory.tscn`. It presents the exact retained
cave, multi-viewer union, and teleport windows from the native
1536x512x1536-cell LOD2/LOD1/LOD0 catalog and fails closed on pinned residency
state. The presentation shader and camera are diagnostic only.

The TQP-41 Adaptive Persistence Observatory is a separate `@tool` scene at
`scenes/adaptive_persistence_observatory.tscn`. It stages the retained
native-baked hierarchy, applies central and distant edits, recreates a fresh
native runtime for replay, and uses supported compaction before inspecting the
distant resource. Direct pre-compaction distant coarse-page meshing and
same-node cross-root restart reuse are explicitly outside the qualified scope.

`tools/run_edit_gate_b_validation.gd` executes the focused `TQP-09` through
`TQP-14` qualification. `tools/capture_edit_qualification_visual.gd`
regenerates the deterministic brush and temporal-edit cross-section reference.

`tools/run_wave_02_validation.gd` executes the focused TQP-18, TQP-19, and
TQP-20 first-batch evidence. `tools/capture_material_blending_visual.gd`
regenerates the deterministic four-panel material-blending reference used by
TQP-18 visual review.

`tools/run_wave_02_second_batch_validation.gd` executes focused TQP-21 and
TQP-22 evidence. The retained observatory image is captured twice on
Forward+/D3D12 and must be byte-identical before it can be reviewed. A second
two-color capture isolates the exact corrected tangent seam.

Terrain Lab scenes may depend on `world_transvoxel_terrain_lab` and the pinned
production dependencies declared by their milestone. They must not depend on
`world_transvoxel_cell_lab`.
