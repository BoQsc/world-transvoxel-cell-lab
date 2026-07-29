# World Transvoxel Cell Lab

This is a separate editor-only addon for close inspection of the Transvoxel
cell/unit primitive used by voxel terrain: regular cells, transition cells, edit
brushes, patch metrics, chunk probes, topology, and runtime readiness. It is
intentionally not terrain-only, but terrain correctness and performance are the
primary validation targets.

## Scope Standard

- Cell-first: the lab treats the regular cell, transition cell, and chunk probe
  as the authoritative building blocks to inspect.
- Terrain-focused: digging, construction, LOD stitching, topology, and rebuild
  cost are judged against volumetric terrain needs first.
- Scalar-field aware: the same Transvoxel primitive can validate non-terrain
  isosurfaces later without changing the core lab identity.
- Native-authoritative: all rendered and reported output must come through
  `world_transvoxel`; the lab must not grow a fallback mesher.
- Evidence-driven: `world_transvoxel` is the implementation under test, not an
  assumption of perfection. Proven lab failures should become reproducible tests
  and upstream fixes.
- Integration-facing: the integration game is a downstream proving ground. Game
  artifacts should be reduced to lab repros, then classified as upstream,
  integration, or gameplay/runtime fixes.

Enable it from:

```text
res://addons/world_transvoxel_cell_lab/plugin.cfg
```

The addon adds:

- `WtTransvoxelCellLab`, a `Node3D` diagnostic primitive that builds a bounded
  editable scalar-field patch in the editor;
- a `World Transvoxel Lab` dock for creating a lab node, expanding the patch,
  applying dig/construct probes, rebuilding, and running a small rebuild
  baseline;
- a grouped validation report panel with contract, regular patch, transition
  cell, production chunk, and baseline sections;
- copyable report JSON and saved repro snapshots for reducing upstream,
  integration, and gameplay/runtime issues to a small case;
- all-case regular cell corpus validation;
- all-case, all-orientation transition cell corpus validation;
- same-LOD chunk seam validation and LOD transition-mask validation;
- deterministic edit-sequence validation;
- performance baseline reporting;
- a smoke script at
  `res://addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd`.

The lab requires `WorldTransvoxelCellProbe` from `res://addons/world_transvoxel`.
It does not include a fallback mesher. All rendered and reported surface output
comes from the official MIT Transvoxel backend and reports:

- render authority and correctness claim;
- backend identity;
- case histogram and native cell status histogram;
- exact transition-cell probe status, case code, orientation, and mesh health;
- native LOD 0 production chunk probe status, samples, mesh size, and mesh
  health;
- 3D probe labels for the editable regular patch, transition cell, and
  production chunk;
- interior open edges, boundary open edges, nonmanifold edges, and shared-edge
  orientation conflicts;
- rebuild timing and edit count.

The authoritative validator covers the regular-cell patch, an isolated native
transition-cell probe, and a finalized native LOD 0 chunk generated through the
production `WtChunkMesher` path.
