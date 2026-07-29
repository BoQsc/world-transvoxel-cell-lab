# World Transvoxel Cell Lab

This is a separate editor-only addon for close inspection of voxel terrain
cells, edit brushes, patch metrics, and runtime readiness. It is intentionally
not part of the production terrain stack.

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
- a smoke script at
  `res://addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd`.

The lab requires `WorldTransvoxelCellProbe` from `res://addons/world_transvoxel`.
It does not include a fallback mesher. All rendered and reported surface output
comes from the official MIT Transvoxel backend and reports:

- render authority and correctness claim;
- backend identity;
- case histogram and native cell status histogram;
- exact transition-cell probe status, case code, orientation, and mesh health;
- interior open edges, boundary open edges, nonmanifold edges, and shared-edge
  orientation conflicts;
- rebuild timing and edit count.

The authoritative validator covers the regular-cell patch plus an isolated
native transition-cell probe.
