# Cell Lab Architecture

## Dependency Direction

```text
world-transvoxel native backend
              |
              v
WorldTransvoxelCellProbe
              |
              v
cell-lab services
              |
              v
WtTransvoxelCellLab scene state
              |
              v
editor dock and standalone scene
```

The lab may expose and test native diagnostic data. It may not copy or replace
the meshing algorithm. The integration game may export suspicious cases to the
lab; it does not define lab correctness.

## Node Responsibility

`WtTransvoxelCellLab` is the live scene orchestrator. It owns:

- exported editor parameters and edit state;
- patch field density, gradient, and material sampling;
- scene roots, materials, and overview mesh instances;
- the public compatibility API used by the dock and tests;
- delegation and persistence of validation results.

It does not own corpus algorithms, repro file I/O, performance policy,
integration classification, or standards execution.

## Services

| Service | Responsibility |
| --- | --- |
| `wt_cell_lab_contracts.gd` | Schemas, authority metadata, face and orientation conventions |
| `wt_cell_lab_mesh_analysis.gd` | Buffer, triangle integrity, component winding, topology, edge, seam, and bounds primitives |
| `wt_cell_lab_case_validator.gd` | Regular/transition corpora and selected-case descriptions |
| `wt_cell_lab_chunk_validator.gd` | LOD probes, same-LOD seams, and coarse/fine fixtures |
| `wt_cell_lab_dependency_provenance.gd` | Runtime backend identity, plugin version, and native artifact verification |
| `wt_cell_lab_authority_validator.gd` | Near-isovalue case stability and vertical same/mixed-LOD seam stress |
| `wt_cell_lab_edit_validator.gd` | Edit sequence, replay, deltas, and terrain fixtures |
| `wt_cell_lab_performance.gd` | Dedicated benchmarks, history, rates, and warnings |
| `wt_cell_lab_repro_store.gd` | Versioned snapshots, JSON conversion, browser listing, and storage |
| `wt_cell_lab_integration_adapter.gd` | Integration snapshot reduction and fix-layer classification |
| `wt_cell_lab_standards_runner.gd` | Committed repro, case, visual, and threshold standards |
| `wt_cell_lab_report_builder.gd` | Canonical live report construction |
| `wt_cell_lab_inspection_presenter.gd` | Selected-case and mixed-LOD close-up rendering |
| `wt_cell_lab_reference_field.gd` | Canonical terrain density, materials, feature catalog, probes, and edit composition |
| `wt_cell_lab_reference_terrain.gd` | Multi-chunk LOD assembly, seam/edit proof, analytic section topology, retained negative fixtures, deterministic signature, and benchmark |
| `wt_cell_lab_terrain_observatory.gd` | Derived terrain views, overlays, density slices, view validation, and observatory benchmark |
| `wt_cell_lab_reference_terrain_presenter.gd` | Rendering of observatory buffers, overlays, selection, labels, and edit markers |

The editor dock owns controls and report presentation only.

## Upstream Boundary

`world-transvoxel` owns:

- Transvoxel lookup tables and meshing behavior;
- regular, transition, and chunk production algorithms;
- diagnostic probe APIs that expose exact backend results;
- fixes proven by minimized lab repros.

The lab owns:

- fields and fixtures used to exercise those APIs;
- comparisons, reports, visualizations, repro metadata, and standards;
- no fallback or alternate meshing path.

The committed dependency manifest identifies the exact native authority under
test. A runtime result is authoritative only when backend identity, plugin
version, and native artifact hashes match that manifest. CI additionally
checks out the pinned source commit and verifies its source trees and
third-party Transvoxel source.

The canonical reference terrain is a standards fixture, not a second terrain
runtime. It directly invokes the upstream production chunk mesher through
`WorldTransvoxelCellProbe`. Streaming policy, scheduling, persistence,
collision, and gameplay remain outside its authority.

## Reference Terrain Layer

The terrain validation chain is intentionally layered:

```text
cell contracts
    -> isolated chunk and LOD fixtures
        -> canonical multi-chunk reference terrain
            -> retained negative terrain fixtures
                -> integration-game reduction
```

The canonical terrain is the first layer that proves regular surfaces,
transition surfaces, same-LOD neighbors, mixed-LOD neighbors, materials,
feature fields, and edits together in one contiguous world-space fixture.
See `REFERENCE_TERRAIN_STANDARD.md` for the exact layout and invariants.

The Terrain Observatory is downstream of that fixture. It can recolor native
buffers, derive lines, sample the canonical field, and hide or isolate existing
buffers. It cannot generate replacement terrain geometry. A view failure fails
observatory validation; it does not substitute another implementation.

Winding validation follows the upstream production contract. Shared edges must
be consistently oriented, each connected component must agree in aggregate
with interpolated SDF normals, and canonical terrain rejects every local
triangle/normal disagreement or ambiguous alignment. Deliberately
under-resolved fields that produce such triangles belong in named negative
fixtures with an analytic invariant and a resolved control, not in a passing
canonical baseline.

## Evidence Rule

A suspected upstream bug requires:

- a minimal reproducible snapshot;
- a native probe failure or contradiction;
- a stated invariant;
- deterministic reproduction;
- focused automated coverage;
- visual evidence when geometry relationships matter.

Until that evidence exists, the lab reports a suspected layer rather than
changing `world-transvoxel`.
