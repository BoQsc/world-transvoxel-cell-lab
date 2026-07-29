# World Transvoxel Cell Lab

Standalone Godot project and editor addon for native-authoritative Transvoxel
terrain validation.

Open:

```text
C:\Users\Windows10_new\Documents\github_repositories\world-transvoxel-cell-lab\project.godot
```

The lab depends exclusively on:

```text
res://addons/world_transvoxel/world_transvoxel.gdextension
```

There is no fallback mesher. Every surface inspected by the lab comes from
`WorldTransvoxelCellProbe` and the production `WtChunkMesher` path in
`world-transvoxel`.

## Standard

The lab is cell-first and terrain-focused. It treats regular cells, transition
cells, chunk composition, LOD seams, edits, topology, materials, provenance,
and cost as one validation chain.

`world-transvoxel` is the implementation authority under test, not an
infallible oracle. A reproducible lab contradiction supported by topology,
native buffer data, visual evidence, and standards tests is grounds for an
upstream correction.

The integration game is a downstream proving ground. Its artifacts should be
reduced to lab snapshots and classified as `world_transvoxel`, `integration`,
`runtime`, or `gameplay` issues before a fix is chosen.

## Editor Workflow

Enable the `World Transvoxel Lab` plugin and use its dock to:

- switch between patch, selected regular case, selected transition case, and
  mixed-LOD inspection;
- expand the patch and apply dig or construct edits;
- run the 256-case regular corpus and 512-case by 6-orientation transition
  corpus;
- validate same-LOD seams, LOD 1-3 transition chunks, and 12 coarse/fine
  neighbor fixtures;
- run deterministic edit sequences and terrain edit fixtures;
- measure cell, transition, chunk, patch, and edit performance;
- browse, label, save, and restore repros;
- import integration-game JSON snapshots and classify the suspected fix layer;
- execute the committed standards corpus.

The default scene opens with rendered native geometry. Inspection modes show
sample states, topology edges, vertex normals, materials, endpoint provenance,
orientation basis, and mixed-LOD seam results.

## Validation

Run the full headless validator:

```text
godot --headless --path . --script tools/run_cell_lab_validation.gd -- all
```

Run the structural smoke test:

```text
godot --headless --path . --script addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd
```

Regenerate committed visual standards with a graphical renderer:

```text
godot --path . --script tools/capture_standard_visuals.gd
```

The CI workflow pins the official Godot 4.7.1 Windows artifact by SHA-256 and
runs the native extension load, smoke test, correctness corpora, standards
corpus, and performance warning pass.

See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership boundaries and
[ROADMAP.md](ROADMAP.md) for completed milestone evidence.
