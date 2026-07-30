# Cell Lab Canonical Reference Terrain Standard

## Purpose

The Reference Terrain is the lab's deterministic terrain-scale standard. It
proves that native regular cells, transition cells, chunks, LOD interfaces,
materials, scalar-field features, and edits remain coherent when assembled
into one contiguous terrain.

It is not a production terrain runtime. Separate qualification services use
this fixture to test deterministic streaming order, persistence, and
exact-mesh collision contracts, but the terrain fixture does not claim
authority over production scheduling, physics policy, multiplayer, or
gameplay.

## Native Authority

Every rendered triangle comes from `world-transvoxel` through
`WorldTransvoxelCellProbe.mesh_chunk_with_callable`, which invokes the
production `WtChunkMesher`. The lab supplies only the deterministic sample
field, fixture layout, comparisons, reports, and visualization. There is no
fallback mesher.

## Layout

The fixture ID is `canonical_lod_ring_v2`.

```text
LOD1   LOD1   LOD1
LOD1  [LOD0 x 4]  LOD1
LOD1   LOD1   LOD1
```

Eight LOD1 chunks form a 3 by 3 outer ring. The missing center LOD1 footprint
is replaced by four LOD0 chunks. The four coarse chunks facing the center own
the required Transvoxel transition surfaces.

The world-space bounds are `(-32, 0, -32)` through `(64, 32, 64)`.

## Field Features

The fixed scalar field contains:

- continuous rolling surface terrain;
- a steep but smooth cliff;
- crossing main and branch tunnels;
- a connected cave chamber;
- an overhang shelf with a carved undercut;
- a volumetric arch with two pillars and an open span;
- a thin vertical fin and adjacent clearance;
- deterministic material strata and regions.

Fifteen signed-density probes permanently verify bedrock, open air, both sides
of the cliff, tunnel and branch air, cave core and shell, overhang and
undercut, arch pillars/opening/crown, and thin-feature solid/clearance.

The canonical main tunnel is deep enough that its minimum analytic roof
clearance exceeds the LOD1 cell size. The former shallow-roof geometry is
retained separately as `coarse_tunnel_roof_alias_v1`; it is a negative fixture,
not passing canonical terrain.

## Required Invariants

A passing result requires:

- all 12 chunks mesh successfully through the native production path;
- all native indices, normals, and materials satisfy buffer contracts;
- no native buffer has nonfinite vertices, degenerate or duplicate triangles,
  nonmanifold edges, shared-edge orientation conflicts, or component-level
  winding/normal conflicts;
- no canonical triangle has a local winding/normal disagreement or ambiguous
  alignment;
- the X=`46.14122` analytic and extracted cross-sections both contain exactly
  two components: terrain surface and tunnel;
- the shallow-roof negative fixture must collapse those components at LOD1,
  recover them at LOD0, and be reported as detected;
- all 12 same-LOD neighbor seam signatures match;
- all four LOD1-to-LOD0 interface signatures match;
- visible crack count is zero;
- repeated full builds produce the same geometry signature;
- all 15 field feature probes match;
- all eight cumulative cross-chunk dig and construct edits change only
  affected chunks;
- affected-chunk ownership includes one LOD-cell of dependency halo around
  chunk sample bounds;
- partial dirty-chunk rebuild output exactly matches full rebuild output;
- all seams still match after each edit;
- clearing and replaying the complete edit sequence produces the identical
  final geometry signature.

## Locked Baseline

The committed standard currently requires:

- 12 chunks: eight LOD1 and four LOD0;
- four chunks with transition surfaces;
- 115,609 native sample calls;
- 11,054 regular triangles;
- 302 transition triangles;
- 11,356 total triangles;
- material IDs `1`, `2`, `3`, `4`, and `6`;
- nine named terrain features and 15 passing signed-density probes;
- seven validated observatory views;
- 1,089 samples and 2,048 triangles in the standard density slice;
- zero mesh-integrity failures, local triangle/normal disagreements, and
  ambiguous alignments;
- canonical section component count `2`, with a minimum tunnel-roof clearance
  of `3.504534` versus LOD1 cell size `2.0`;
- negative-fixture section component counts `1` at LOD1 and `2` at LOD0,
  retaining eight coarse disagreements and zero fine disagreements;
- 589 normal lines;
- 16 tested seam interfaces containing 511 matched exact edge signatures and
  zero unmatched edges;
- 2,304 near-isovalue cell probes at `1e-7`, `1e-5`, and `1e-3`;
- two nonempty vertical same-LOD interfaces and two vertical mixed-LOD
  interfaces;
- geometry SHA-256
  `984e632ab2940fc2658debfce3c0dae672d1462cb9572045424be0b7c62c89df`.

These values are not assumed to be eternally correct. A deliberate upstream
correction may change them, but only with a minimized repro, a stated
invariant, deterministic evidence, review of the owning layer, and an
intentional standards update.

## Inspection Workflow

Choose `Reference Terrain` in the editor dock. The Terrain Observatory offers
seven views:

- `Surface` uses deterministic elevation and slope cues for shape inspection;
- `LOD` separates coarse and fine native buffers;
- `Material` uses high-contrast material-ID colors;
- `Triangles` exposes every native triangle edge;
- `Normals` encodes and draws sampled native normals;
- `Seams` frames all tested same-LOD and mixed-LOD interfaces and transition
  ownership, with failures in red;
- `Density` overlays a movable X, Y, or Z scalar-field slice and sample crosses.

Diagnostic views receive a selected-chunk AABB outline. Surface mode keeps that
outline hidden unless chunk bounds or isolation are requested. Chunk isolation,
chunk bounds, transition visibility, feature labels, and each diagnostic
overlay can be toggled independently. All view settings are preserved in repro
snapshots.

Move the terrain cursor, set the edit radius, and apply `Terrain Dig` or
`Terrain Construct`. `Clear Terrain` restores the canonical field. Run
`Reference Terrain` validation for the full seam, buffer, feature, topology
separation, retained negative-fixture, determinism, incremental-edit, and
seven-view observatory proof.

Ten committed terrain images provide reviewed regression references for the
surface, LOD, material, triangle, normal, seam, density, coarse tunnel-mouth,
arch/thin-fin, and overhang-cutaway presentations. Together with the four
primitive/fixture images, the corpus contains 14 images. These references
detect presentation drift; numeric terrain invariants remain the correctness
gate. See `VISUAL_EVIDENCE_STANDARD.md`.
