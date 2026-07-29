# World Transvoxel Cell Lab Roadmap

The lab standard is cell-first Transvoxel validation, terrain-focused,
native-authoritative, reproducible, measurable, visually inspectable, and
evidence-driven.

`world_transvoxel` is the implementation authority under test. The integration
game is a downstream proving ground, not the correctness authority. Lab evidence
should reduce suspicious behavior into small repros and classify the fix layer:
upstream `world_transvoxel`, integration, or gameplay/runtime.

## Milestone 1: Contract And Authority

Status: first pass complete.

- Separate standalone Godot project and addon.
- Native `world_transvoxel` dependency only.
- No lab fallback mesher.
- Report fields for scope, authority model, upstream correction policy, and
  integration-game diagnostic policy.
- Smoke coverage for the contract fields.

## Milestone 2: Validation Report Panel

Status: first pass complete.

- Grouped editor dock report for contract, regular patch, transition cell,
  production chunk, baseline, and corpus sections.
- Copyable report JSON.
- PASS/FAIL summary driven by report data.

## Milestone 3: Repro Snapshots

Status: first pass complete.

- Save repro snapshots with parameters, edits, report, and authority metadata.
- Apply repro snapshots back onto a lab node.
- Load the latest saved repro from the dock.
- Smoke coverage for repro schema and restore behavior.

Next:

- Add a repro browser.
- Add repro names, notes, expected failure labels, and source layer labels.
- Add repro corpus files committed to the repo when they represent standards or
  fixed bugs.

## Milestone 4: Regular Cell Corpus

Status: first pass complete.

- Sweep all 256 regular cases through `WorldTransvoxelCellProbe`.
- Check empty classification, backend status, buffer validity, and determinism.
- Expose results in the dock and smoke test.

Next:

- Add selected-case visualization.
- Show corner densities, case code, edge intersections, materials, normals, and
  backend endpoint provenance.
- Save any failed case directly as a repro.

## Milestone 5: Transition Cell Corpus

Status: first pass complete.

- Sweep all 512 transition cases across 6 orientations.
- Check empty classification, orientation status consistency, count consistency,
  buffer validity, determinism, and transition prism bounds.
- Expose results in the dock and smoke test.

Next:

- Add selected transition case visualization.
- Show high-resolution side, low-resolution side, stitching edges, transition
  case code, and orientation basis.
- Add transition-specific repro capture.

## Milestone 6: Chunk And LOD Validation

Status: first pass complete.

- Current lab shows a native LOD 0 chunk generated through `WtChunkMesher`.
- Current report checks chunk status, samples, vertices, triangles, nonmanifold
  edges, and orientation conflicts.
- Same-LOD adjacent chunk seam signatures are compared across X, Y, and Z.
- LOD 1 transition-mask chunk generation is validated across all six faces.
- Chunk LOD results are shown in the dock and covered by smoke tests.

Next:

- Add LOD 1+ chunk probes.
- Add mixed-LOD neighbor validation.
- Add visible crack checks between coarse and fine neighbor fixtures.
- Classify chunk failures separately from cell failures.

## Milestone 7: Edit Simulation

Status: first pass complete.

- Dig and construct edit probes exist.
- Edit count and rebuild timing are reported.
- Repro snapshots capture edit sequences.
- A deterministic edit-sequence validator checks topology and production chunk
  health across initial, dig, construct, and second-dig steps.
- Edit sequence results are shown in the dock and covered by smoke tests.

Next:

- Track affected cells and dirty regions.
- Show before/after mesh and report deltas.
- Add edit sequence corpus tests.
- Add terrain-relevant construction, digging, tunnel, overhang, and thin-feature
  fixtures.

## Milestone 8: Performance Baselines

Status: first pass complete.

- Dock baseline action measures rebuild average and maximum time.
- Performance baselines report patch rebuild, chunk LOD validation, edit
  sequence validation, and already-run corpus timings.
- Performance results are shown in the dock and covered by smoke tests.

Next:

- Add dedicated regular-cell, transition-cell, chunk, and edit benchmarks.
- Store baseline history.
- Warn on performance regression thresholds.
- Report triangles/ms, samples/ms, and edit rebuild cost.

## Milestone 9: Integration Game Reduction

Status: policy documented.

- The lab is the reduction target for suspicious integration-game terrain or
  rendering artifacts.

Next:

- Add an import path for small integration-game case snapshots.
- Preserve suspected source layer in repro metadata.
- Add comparison reports that separate backend, integration, and runtime issues.

## Milestone 10: CI And Standards Corpus

Status: smoke test active.

- Current smoke checks the lab contract, native probes, repro restore, regular
  corpus, transition corpus, chunk probe, chunk LOD seams, transition masks,
  edit sequence validation, and performance baselines.

Next:

- Add committed repro corpus tests.
- Add CI jobs for headless Godot validation.
- Add performance warning thresholds.
- Add screenshot/visual validation for selected standard cases.
