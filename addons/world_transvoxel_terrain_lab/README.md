# World Transvoxel Terrain Lab Addon

The Terrain Lab addon owns controlled experiments for the Terrain Qualification
Program. It is separate from `world_transvoxel_cell_lab` even though both addons
share this repository and the pinned `world_transvoxel` dependency.

Current status: fail-closed program revision 37. All 71 milestones have a
machine-readable evidence state. TQP-01 through TQP-47 retain their bounded
qualified scopes; TQP-28 through TQP-43 establish the deterministic native
field contract, LOD0 complex-field corpus, bounded adaptive selector, and
native transition-assembly matrix, boundary/enclosure policy, and independent
geometry/topology oracles plus the seeded adversarial/minimized corpus, dynamic
LOD publication, exact edit invalidation, and bounded adaptive digging and
construction with lifecycle/refinement identity, adaptive material continuity,
and bounded render/collision/query/physics plus consumer-derived navigation
agreement, multi-layer adaptive streaming/residency, and bounded native-baked
adaptive persistence with fresh-runtime replay, and the retained implicit
procedural hierarchy with sparse large-world compaction, plus the retained
fault-order, fail-closed admission, generation-trace, and cross-order runtime
convergence contract. TQP-44 through TQP-47 additionally qualify the accepted
visual corpus, fast-arrival edits, targeted collision, and bounded rendering
regression envelope. TQP-48 through TQP-50 are `implemented` but unqualified
and cover GPU-board WPF60 low-power profiles, soak, and Gate E. TQP-51 through TQP-57 own the
standalone CPU release, TQP-58 through TQP-64 own GPU qualification and release,
and TQP-65 through TQP-71 keep game-oriented systems after terrain release.

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
structural policy, observability, and backend decisions. It qualifies only the
bounded native adaptive-terrain scopes backed by retained evidence and records
the remaining gaps without widening those claims. These reference models are
not a production terrain runtime. GPU and production milestones remain blocked
and no fallback mesher exists.

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

TQP-27 Large Terrain Observatory:

```text
res://labs/terrain_lab/scenes/large_terrain_observatory.tscn
```

Open it from **Project > Tools > Open TQP-27 Large Terrain Observatory**. Its
`@tool` root starts the exact retained 128x16x128-chunk native profile and
streams bounded render and collision windows while displaying the complete
2048x256x2048-cell envelope and live residency state. In the editor, moving the
3D viewport camera streams the horizontal viewer position; Inspector teleport
controls provide the retained origin, center, and distant locations. Running
the scene provides the same teleport controls and a free camera. The scene does
not instantiate the entire catalog as resident geometry and does not extend
TQP-27's bounded qualification claim.

TQP-32 Boundary Observatory:

```text
res://labs/terrain_lab/scenes/boundary_enclosure_observatory.tscn
```

Open it from **Project > Tools > Open TQP-32 Boundary Observatory**. Its
`@tool` root switches among the retained closed-volume, closed-terrain, and
intentionally-open native fixtures. The panel reports contour classification,
interior openings, nonmanifold edges, and outside-field gradient-halo samples;
it never generates caps, skirts, or fallback geometry outside
`WorldTransvoxelCellProbe`.

TQP-33 Independent Oracle Observatory:

```text
res://labs/terrain_lab/scenes/independent_oracle_observatory.tscn
```

Open it from **Project > Tools > Open TQP-33 Independent Oracle**. It displays
the clean native closed assembly or representative injected defects and reports
the independent checks that reject each defect. The oracle consumes normalized
native triangle data and does not call the existing native evidence validator.

TQP-34 Adversarial Corpus Observatory:

```text
res://labs/terrain_lab/scenes/adversarial_corpus_observatory.tscn
```

Open it from **Project > Tools > Open TQP-34 Adversarial Corpus**. Its `@tool`
root switches among four seeded generated cases and three fixed corrected-
regression cases,
four completion-order replays, and optional seed overrides. It renders only
native geometry and reports the independent TQP-33 verdict, case seed, replay
order, chunk/triangle counts, components, Euler characteristic, and materials.

TQP-37 Adaptive Edit Observatory:

```text
res://labs/terrain_lab/scenes/adaptive_edit_observatory.tscn
```

Open it from **Project > Tools > Open TQP-37 Adaptive Editing**. Its `@tool`
root runs only the native world-transvoxel runtime and exposes isolated seam
carve, corner construction, repeated tunnel, under-resolved coarse/refined,
unloaded edit, and reconstructive-history fixtures. The panel reports field,
local triangle, edit-retention, render, and collision state. Its bounded 48/64
collision profile is a correctness fixture, not a production collision-policy
or low-power performance qualification.

TQP-38 Adaptive Surface Observatory:

```text
res://labs/terrain_lab/scenes/adaptive_surface_observatory.tscn
```

Open it from **Project > Tools > Open TQP-38 Adaptive Surface**. Its `@tool`
root exposes lit, material-ID, and native generated/authored provenance views,
plus a deterministic LOD cycle and fixture reset. Native payload and
authoritative samples remain the evidence authority; shader presentation and
captures are diagnostic.

TQP-39 Adaptive System Observatory:

```text
res://labs/terrain_lab/scenes/adaptive_system_observatory.tscn
```

Open it from **Project > Tools > Open TQP-39 Adaptive System**. Its `@tool`
root overlays complete demanded native collision triangles, consumer-derived
walkable triangles, and authoritative-query ray fixtures over the cave,
overhang, thin construction, and staged-crater fixture. It exposes teleport
retirement, staged replacement, and reset controls. Navigation is explicitly a
Godot consumer derivative, not world-transvoxel authority.

TQP-40 Adaptive Streaming Observatory:

```text
res://labs/terrain_lab/scenes/adaptive_streaming_observatory.tscn
```

Open it from **Project > Tools > Open TQP-40 Adaptive Streaming**. Its `@tool`
root exposes the pinned cave, multi-viewer union, and far-teleport residency
windows over the native LOD2/LOD1/LOD0 procedural catalog. It reports exact
active and per-LOD counts and fails when the retained native state changes.

TQP-41 Adaptive Persistence Observatory:

```text
res://labs/terrain_lab/scenes/adaptive_persistence_observatory.tscn
```

Open it from **Project > Tools > Open TQP-41 Adaptive Persistence**. Its
`@tool` root stages the retained 44-page native-baked fixture, applies the
central and distant transactions, recreates a fresh native runtime for journal
replay, and compacts before loading the distant edited resource. It has no
procedural or mesh fallback.

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

Focused TQP-34 adversarial corpus report:

```text
res://labs/terrain_lab/tools/run_adversarial_corpus_validation.gd
```

Focused TQP-38 adaptive surface report:

```text
res://labs/terrain_lab/tools/run_adaptive_surface_validation.gd
```

Focused TQP-39 adaptive system report:

```text
res://labs/terrain_lab/tools/run_adaptive_system_validation.gd
```

Focused TQP-40 adaptive streaming report:

```text
res://labs/terrain_lab/tools/run_adaptive_streaming_validation.gd
```

Focused TQP-41 adaptive persistence report:

```text
res://labs/terrain_lab/tools/run_adaptive_persistence_validation.gd
```
