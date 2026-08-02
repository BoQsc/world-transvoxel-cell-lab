# World Transvoxel Terrain Lab Addon

The Terrain Lab addon owns controlled experiments for the Terrain Qualification
Program. It is separate from `world_transvoxel_cell_lab` even though both addons
share this repository and the pinned `world_transvoxel` dependency.

Current status: complete fail-closed program execution. All 46 milestones have
machine-readable contracts, evidence states, executable coverage, or explicit
external blockers. No milestone is left `proposed`.

Gate B edit qualification is retained in
`standards/edit_gate_b_standard.json`. It qualifies `TQP-09` through `TQP-14`
for their declared CPU/Windows reference scopes while leaving worker
concurrency, production collision scheduling, networking, GPU execution, and
production frame-time performance explicitly unqualified.

## Allowed Dependencies

- `world_transvoxel` is the current required native test dependency.
- `world_transvoxel_terrain` may become a pinned test dependency after a
  specified milestone requires production-layer comparison.

## Forbidden Dependencies

- Terrain Lab code must not preload, instantiate, or extend Cell Lab code.
- Cell Lab code must not preload, instantiate, or extend Terrain Lab code.
- Production projects must not depend on either lab addon at runtime.

The addon provides deterministic reference implementations and qualification
fixtures for edit semantics, material semantics, terrain-system policy,
structural policy, observability, and backend decisions. These reference
models are not a production terrain runtime. GPU and production milestones
remain blocked and no fallback mesher exists.

Program document:

```text
res://docs/terrain_lab/TERRAIN_QUALIFICATION_PROGRAM.md
```

Boundary smoke:

```text
res://addons/world_transvoxel_terrain_lab/tests/wt_terrain_lab_smoke.gd
```

Terrain Observatory:

```text
res://labs/terrain_lab/scenes/terrain_observatory.tscn
```

The observatory root is an `@tool` Node3D. Open it from **Project > Tools >
Open Terrain Observatory**, select the root node, and use the **Editor Preview**
and **Editor Brush** Inspector groups to rebuild/reset the canonical fixture or
apply live dig and construction operations. The generated editor mesh uses the
pinned native `world_transvoxel` dependency; there is no fallback path. The
status is fail-closed on exact boundary-edge agreement across all adjacent
same-LOD chunks, including the canonical tangent-edit regression retained by
`TQP-D011`.

TQP-23 guided surface review:

```text
res://labs/terrain_lab/scenes/surface_shading_review.tscn
```

Open it from **Project > Tools > Open TQP-23 Surface Review**. Its root is an
`@tool` node with Inspector controls for the diagnostic mode, camera endpoint,
and motion preview. Running the scene adds a deterministic near/far camera
cycle, ten diagnostic views, eight required observations, an explicit on/off
shadow comparison, and fail-closed draft verdict recording. Drafts are written under `user://`; they cannot
qualify TQP-23 without a separate repository decision.

Full machine report:

```text
res://labs/terrain_lab/tools/run_terrain_lab_validation.gd
```

Focused Gate B report:

```text
res://labs/terrain_lab/tools/run_edit_gate_b_validation.gd
```

Focused Wave 02 first-batch report:

```text
res://labs/terrain_lab/tools/run_wave_02_validation.gd
```

Focused Wave 02 second-batch report:

```text
res://labs/terrain_lab/tools/run_wave_02_second_batch_validation.gd
```
