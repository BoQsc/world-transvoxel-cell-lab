# World Transvoxel Cell Lab Addon

The addon provides the `WtTransvoxelCellLab` editor node and the
`World Transvoxel Lab` dock.

## Scope

- Native `world-transvoxel` dependency only.
- Regular and transition cell inspection with exact backend buffers.
- Production chunk, same-LOD, and mixed-LOD validation.
- Canonical 12-chunk Reference Terrain with exact seam, feature, edit,
  topology-separation, determinism, performance, numeric, and visual standards.
- Named negative terrain fixtures with analytically resolved LOD controls.
- Pinned native dependency provenance and runtime artifact verification.
- Near-isovalue cell stability and vertical same/mixed-LOD authority stress.
- Adversarial scalar fields, minimized native repros, and independent
  interpolation/table-property checks.
- Terrain edit fixtures, dirty-region accounting, and before/after deltas.
- Seeded edit stress, scaling, native-buffer memory, rendering-input,
  exact-face collision, streaming-order, and persistence qualification.
- Integration parity, explicit platform/renderer scope, hashed release
  evidence, visual diffs, and upstream-correction governance.
- Repro storage, integration reduction, performance history, and committed
  standards.

## Ownership

`WtTransvoxelCellLab` owns editable scene state, scalar-field sampling, and
visual roots. Focused services under `lab/services` own contracts, mesh
analysis, cell corpora, chunk validation, dependency provenance, authority
stress, edit validation, performance, repro storage, integration import,
standards execution, report construction, reference-terrain validation, and
inspection presentation. Additional correctness, runtime, and release
qualification services own milestones 16-29; the root node only delegates and
presents their results.

The addon must not implement an alternate Transvoxel mesher. Diagnostic APIs
needed from the backend belong in `world-transvoxel`; editor UI, fixtures,
reports, and standards belong here.

Enable:

```text
res://addons/world_transvoxel_cell_lab/plugin.cfg
```

Headless validation:

```text
res://tools/run_cell_lab_validation.gd
```

Use the dock's `Qualification 16-29` command for the complete qualification
report, or run the headless validator with the `qualification` stage.

Structural smoke:

```text
res://addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd
```
