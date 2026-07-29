# World Transvoxel Cell Lab Roadmap

The roadmap standard is cell-first, terrain-focused, native-authoritative,
reproducible, measurable, visually inspectable, and evidence-driven.

Milestones 1 through 29 are complete for the scope locked by
`addons/world_transvoxel_cell_lab/standards/qualification_standard.json`.
Completion does not silently broaden platform or runtime authority: unsupported
targets remain explicitly unqualified in the platform matrix. Future milestones
must preserve the ownership boundaries in `ARCHITECTURE.md` and add committed
evidence before claiming a broader correctness domain.

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

## Milestone 16: Adversarial Scalar Fields

Status: complete.

- Ten named fields cover diagonals, offsets, saddles, gyroids, high curvature,
  resolved thin layers and tunnels, near-cancellation, and two deterministic
  seeded warps.
- Twenty LOD0/LOD1 native probes lock 21,368 triangles and an exact aggregate
  signature.
- Four known under-resolved results remain named negative detections; any new
  integrity, determinism, or topology failure fails qualification.

## Milestone 17: Failure Localization And Minimization

Status: complete.

- The retained coarse tunnel alias is reduced from terrain scale to one native
  regular cell.
- The standard locks case code `124`, owning cell `(5, 4, 8)`, eight scalar
  samples, and two reproduced local disagreements.
- The minimized fixture remains connected to its resolved control and source
  terrain repro.

## Milestone 18: Independent Specification Checks

Status: complete.

- Independent interpolation and bracketing checks cover 1,536 regular and
  4,096 transition intersections.
- Forty-eight orientation probes and 384 complement pairs exercise table
  orientation and topology properties without implementing a second mesher.
- Complement topology asymmetry is measured, not falsely assumed invariant;
  the locked corpus currently records 137 asymmetries.

## Milestone 19: Edit Stress Corpus

Status: complete.

- Twenty-four seeded dig/construct operations include overlap, cancellation,
  duplicate application, and boundary edits.
- Four checkpoints prove incremental/full equivalence and exact replay.
- Dirty ownership includes a one-cell LOD dependency halo so samples consumed
  by neighboring chunks are never omitted.

## Milestone 20: Scaling Baselines

Status: complete.

- Six scenarios vary chunk width, LOD, active-cell density, and field
  complexity.
- Counts, timings, throughput, 5,579 triangles, and an aggregate geometry
  signature are machine-readable.

## Milestone 21: Memory And Buffer Reuse

Status: complete.

- Sixteen canonical native buffers account for 317,516 payload bytes.
- Repeated inspection proves stable buffer accounting and rejects unexpected
  churn in the measured canonical build.

## Milestone 22: Rendering Quality

Status: complete.

- 6,473 tangent-basis samples are checked for finite, normalized,
  SDF-consistent orientation.
- Material IDs `1`, `2`, `3`, `4`, and `6`, lighting inputs, precision, and
  camera-distance transforms are qualified.

## Milestone 23: Collision And Queries

Status: complete.

- An exact `ConcavePolygonShape3D` is built from all 11,356 rendered terrain
  faces.
- Nine vertical mesh/SDF query comparisons lock collision agreement against
  the authoritative field and rendered geometry.

## Milestone 24: Streaming Simulation

Status: complete.

- Three load/rebuild schedules perform 36 chunk builds.
- Build-order independence, moving-window seam stability, and stale request
  rejection are required.
- This is deterministic policy simulation, not a claim that the lab is a
  production streaming runtime.

## Milestone 25: Persistence

Status: complete.

- Eight edits, field identity, chunk versions, and geometry signatures survive
  deterministic JSON write/read.
- Payload checksum verification detects corruption before reload acceptance.

## Milestone 26: Integration Parity

Status: complete.

- Three committed integration fixtures cover five reduced operations and two
  ownership classifications.
- A downstream passing debug/edit snapshot and a retained watertightness
  failure prove that parity does not erase ownership distinctions.

## Milestone 27: Platform And Renderer Matrix

Status: complete for declared scope.

- Windows/x86_64 debug and release native artifacts are required.
- `gl_compatibility`, `mobile`, and `forward_plus` renderer lanes are declared
  and validated by CI configuration.
- Five unavailable artifact targets are explicitly unqualified. They are not
  counted as failures or represented as supported.

## Milestone 28: Release Qualification Bundle

Status: complete.

- Ten core evidence files, 11 visual standards, and the locked qualification
  standard form a machine-readable release bundle.
- SHA-256 and byte counts reject stale evidence; pixel comparison validates
  candidate visuals while tolerating narrowly defined renderer variance.

## Milestone 29: Upstream Correction Governance

Status: complete.

- A machine-readable governance registry requires eight evidence classes:
  repro, invariant, ownership, determinism, focused test, visual evidence,
  review, and downstream parity.
- One retained topology-alias case exercises the process.
- No upstream correction is marked confirmed without all required evidence.

See `QUALIFICATION_STANDARD.md` for execution commands, exact scope, retained
negative results, and interpretation rules.

## Next Standard

New work starts only from evidence:

1. Add a minimal committed repro for a newly discovered behavior.
2. Classify the suspected ownership layer.
3. Add or strengthen an invariant that fails for the repro.
4. Correct the owning layer.
5. Keep the fixed repro as a permanent standard.
