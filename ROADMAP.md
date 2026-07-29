# World Transvoxel Cell Lab Roadmap

The roadmap standard is cell-first, terrain-focused, native-authoritative,
reproducible, measurable, visually inspectable, and evidence-driven.

Milestones 1 through 15 are complete. Future milestones must preserve the
ownership boundaries in `ARCHITECTURE.md` and add committed evidence before
claiming a broader correctness domain.

## Milestone 1: Contract And Authority

Status: complete.

- Standalone project and addon.
- Native `world-transvoxel` dependency with no fallback mesher.
- Explicit authority, scope, upstream-correction, and integration-game policy.
- Smoke coverage for every contract field.

## Milestone 2: Validation Report Panel

Status: complete.

- Grouped editor report for all live probes, corpora, edits, performance,
  integration reduction, repros, and standards.
- Copyable JSON and report-driven PASS/FAIL state.
- Validation results persist across visual rebuilds.

## Milestone 3: Repro Snapshots

Status: complete.

- Versioned repro save/restore with parameters, edits, report, and authority.
- Repro browser for user and committed snapshots.
- Name, notes, expected label, source layer, and source reference metadata.
- Three committed terrain standards.

## Milestone 4: Regular Cell Corpus

Status: complete.

- All 256 cases validated for status, emptiness, buffers, materials, endpoint
  provenance, and determinism.
- Selected-case rendering shows densities, case code, sample states, edge
  intersections, materials, normals, and backend endpoints.
- Unique failures are automatically saved as focused repros.

## Milestone 5: Transition Cell Corpus

Status: complete.

- All 512 cases across all 6 orientations.
- Status/count consistency, prism bounds, buffers, materials, provenance, and
  determinism.
- Selected transition rendering shows high-resolution samples,
  low-resolution aliases, stitching edges, orientation basis, and normals.
- Unique transition failures are automatically saved with orientation.

## Milestone 6: Chunk And LOD Validation

Status: complete.

- Native LOD 0 overview probe and LOD 1-3 all-face probes.
- Same-LOD seams validated across X, Y, and Z for LOD 0-2.
- Mixed LOD 1-to-0 and 2-to-1 validation on all six faces.
- Each mixed fixture compares one coarse transition surface with four fine
  neighbors in world space.
- Zero unmatched interface edges is the visible-crack standard.
- Chunk and LOD failures are classified separately from cell failures.

## Milestone 7: Edit Simulation

Status: complete.

- Deterministic dig/construct sequence with replay equivalence.
- Affected-cell and dirty-region tracking.
- Before/after vertex, triangle, active-cell, and timing deltas.
- Construction, digging, tunnel, overhang, and thin-feature fixtures.
- Material IDs and topology health included in reports and repros.

## Milestone 8: Performance Baselines

Status: complete.

- Dedicated regular-cell, transition-cell, chunk, patch, and edit timings.
- Triangles/ms, samples/ms, and edit rebuild cost.
- Persistent local baseline history.
- Relative regression warnings and committed absolute warning limits.

## Milestone 9: Integration Game Reduction

Status: complete.

- JSON import for integration debug, edit, watertightness, and lab snapshots.
- Imported operations reduce to native lab edits.
- Repros preserve integration source metadata.
- Comparison reports classify suspected backend, integration, or runtime
  ownership.

## Milestone 10: CI And Standards Corpus

Status: complete.

- Committed repro and selected-case signature standards.
- Eleven rendered visual references with dimensions, nonblank checks, and
  SHA-256 locks.
- Headless smoke and full-suite runner.
- Windows CI with the official Godot 4.7.1 artifact pinned by SHA-256.
- CI verification of the pinned `world-transvoxel` source commit, source
  trees, backend revision, plugin version, and native artifact hashes.
- Performance warning thresholds included in CI output.

## Milestone 11: Canonical Reference Terrain

Status: complete.

- One contiguous deterministic 12-chunk terrain fixture.
- Eight LOD1 chunks form an outer ring; four LOD0 chunks replace its center.
- Four production transition surfaces connect the coarse ring to the fine
  center.
- Terrain field includes surface relief, a tunnel, an overhang shelf, a thin
  feature, and authored material regions.
- All 12 same-LOD neighbor pairs and all four mixed-LOD interfaces compare
  exact world-space seam signatures.
- Native buffers, normals, materials, finite positions, triangle integrity,
  topology, and deterministic geometry signature are validated.
- An eight-step cumulative cross-chunk edit sequence proves partial
  dirty-chunk rebuilds against full rebuilds, reruns seam validation, and
  requires an exact clear-and-replay result.
- Reference-terrain sample and triangle throughput are included in performance
  baselines.
- The standalone scene opens directly in Reference Terrain inspection with
  chunk selection, editable cursor, bounds, LOD colors, transitions, and edit
  markers.
- Committed numeric and SHA-256 geometry standards plus a rendered visual
  standard protect the canonical result.

## Milestone 12: Terrain Observatory

Status: complete.

- Seven switchable views: surface, LOD, material, triangles, normals, seams,
  and density.
- Selected-chunk isolation, transition visibility, bounds, and feature-label
  controls.
- Movable X/Y/Z density slice with 1,089 authoritative field samples, color
  classification, and sample crosses.
- Native normal vectors, exact same-LOD and mixed-LOD edge signatures,
  transition ownership frames, and explicit unmatched-edge overlays.
- Repro snapshots preserve every observatory control.
- All views, isolation, transition toggling, and overlay counts have automated
  validation and a locked standards signature.
- Dedicated all-view timing is included in performance history and thresholds.

## Milestone 13: Reference Terrain Quality

Status: complete.

- Canonical field responsibility is isolated from terrain assembly.
- Terrain includes rolling hills, cliff, crossing tunnels, connected cave,
  undercut overhang, volumetric arch, thin fin, and material strata.
- Nine named features and 15 signed-density probes are permanently validated.
- Exact same-LOD and mixed-LOD seam signatures still pass after the richer
  field and after cross-chunk edits.
- Epsilon-sensitive boundary degeneracy is excluded by a non-coplanar
  deterministic field baseline.
- Surface, LOD, materials, triangles, normals, seams, and density are
  committed as terrain visual standards.
- The geometry, feature, seam, and observatory signatures are locked together
  in the canonical reference-terrain standard.

## Milestone 14: Authority Hardening

Status: complete.

- A committed native dependency manifest pins the `world-transvoxel` source
  commit and trees, Godot C++ revision, plugin version, official Transvoxel
  source hash, backend identity, and shipped DLL hashes.
- Runtime validation and CI source-checkout verification reject dependency
  drift before correctness claims are accepted.
- Mesh validation rejects nonfinite vertices, degenerate triangles, duplicate
  triangles, nonmanifold edges, shared-edge orientation conflicts, and
  component-level winding/normal conflicts.
- Canonical terrain rejects per-triangle normal disagreements and ambiguous
  alignments; both counts are zero.
- Seam view rendering is derived from the exact signatures under test:
  511 matched edges and zero unmatched edges across 16 interfaces.
- All 256 regular and 512 transition cases are exercised at three signed
  near-isovalue magnitudes, totaling 2,304 stability probes.
- A three-chunk vertical stack verifies two nonempty same-LOD Y interfaces;
  both negative-Y and positive-Y mixed-LOD interfaces are also required.
- The canonical eight-step dig/construct workflow spans all fine chunks and
  shared boundaries and must replay to an identical final geometry hash.
- LOD, triangle, and normal visual standards complete the 11-image corpus.

## Milestone 15: Topology Separation Standard

Status: complete.

- The canonical main-tunnel roof has `3.504534` minimum analytic clearance,
  exceeding the LOD1 cell size of `2.0`.
- A non-grid X cross-section must contain exactly two extracted components,
  matching the separate analytic terrain and tunnel surfaces.
- The former shallow-roof canonical geometry is retained as
  `coarse_tunnel_roof_alias_v1`, with positive analytic clearance below one
  LOD1 cell.
- The negative fixture must reproduce one merged LOD1 section component and
  eight local winding/normal disagreements while its LOD0 control recovers two
  components and zero disagreements.
- Numeric standards and smoke coverage lock the retained failure detector;
  regenerated visual terrain baselines lock the corrected canonical fixture.

## Future Milestones

16. Broader adversarial scalar-field corpus: ambiguous cases, high curvature,
    cancellation, thin-feature limits, and deterministic fuzz seeds.
17. Failure localization and minimization: select unmatched seam signatures,
    jump to owning cells, and export the smallest native repro.
18. Independent specification checks: table invariants and topology properties
    that do not duplicate or replace the production mesher.
19. Edit stress corpus: randomized but seeded long dig/construct sequences,
    cancellation, overlapping edits, and incremental/full equivalence.
20. Scaling baselines: chunk size, LOD depth, active-cell ratio, and feature
    complexity distributions rather than single timings.
21. Memory and allocation observability: peak memory, buffer churn, reuse, and
    per-stage allocation budgets.
22. Rendering quality qualification: tangents, material blending, lighting,
    precision, and camera-distance artifacts.
23. Collision and query qualification against the exact rendered geometry.
24. Streaming simulation: load/unload order, moving LOD windows, stale work,
    and boundary stability.
25. Persistence standards for fields, edits, chunk versions, and deterministic
    reloads.
26. Integration-game parity corpus reduced to canonical lab fixtures.
27. Platform and renderer matrix across supported Godot targets.
28. Release qualification bundles with machine-readable evidence and visual
    diffs.
29. Upstream correction governance: minimized repro, invariant, fix review,
    retained regression standard, and downstream parity proof.

## Next Standard

New work starts only from evidence:

1. Add a minimal committed repro for a newly discovered behavior.
2. Classify the suspected ownership layer.
3. Add or strengthen an invariant that fails for the repro.
4. Correct the owning layer.
5. Keep the fixed repro as a permanent standard.
