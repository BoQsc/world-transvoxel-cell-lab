# World Transvoxel Cell Lab Roadmap

The roadmap standard is cell-first, terrain-focused, native-authoritative,
reproducible, measurable, visually inspectable, and evidence-driven.

All original milestones are complete. Future milestones must preserve the
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
- Four rendered visual references with dimensions, nonblank checks, and
  SHA-256 locks.
- Headless smoke and full-suite runner.
- Windows CI with the official Godot 4.7.1 artifact pinned by SHA-256.
- Performance warning thresholds included in CI output.

## Next Standard

New work starts only from evidence:

1. Add a minimal committed repro for a newly discovered behavior.
2. Classify the suspected ownership layer.
3. Add or strengthen an invariant that fails for the repro.
4. Correct the owning layer.
5. Keep the fixed repro as a permanent standard.
