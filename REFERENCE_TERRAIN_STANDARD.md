# Canonical Reference Terrain Standard

## Purpose

The Reference Terrain is the lab's deterministic terrain-scale standard. It
proves that native regular cells, transition cells, chunks, LOD interfaces,
materials, scalar-field features, and edits remain coherent when assembled
into one contiguous terrain.

It is not a production terrain runtime. It does not claim authority over
streaming, scheduling, persistence, collisions, multiplayer, or gameplay.

## Native Authority

Every rendered triangle comes from `world-transvoxel` through
`WorldTransvoxelCellProbe.mesh_chunk_with_callable`, which invokes the
production `WtChunkMesher`. The lab supplies only the deterministic sample
field, fixture layout, comparisons, reports, and visualization. There is no
fallback mesher.

## Layout

The fixture ID is `canonical_lod_ring_v1`.

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

## Required Invariants

A passing result requires:

- all 12 chunks mesh successfully through the native production path;
- all native indices, normals, and materials satisfy buffer contracts;
- no native buffer has nonmanifold edges or orientation conflicts;
- all 12 same-LOD neighbor seam signatures match;
- all four LOD1-to-LOD0 interface signatures match;
- visible crack count is zero;
- repeated full builds produce the same geometry signature;
- all 15 field feature probes match;
- cross-chunk dig and construct edits change only affected chunks;
- partial dirty-chunk rebuild output exactly matches full rebuild output;
- all seams still match after each edit.

## Locked Baseline

The committed standard currently requires:

- 12 chunks: eight LOD1 and four LOD0;
- four chunks with transition surfaces;
- 115,406 native sample calls;
- 10,844 regular triangles;
- 298 transition triangles;
- 11,142 total triangles;
- material IDs `1`, `2`, `3`, `4`, and `6`;
- nine named terrain features and 15 passing signed-density probes;
- seven validated observatory views;
- 1,089 samples and 2,048 triangles in the standard density slice;
- 636 normal lines, 20 passing seam overlays, and zero failing overlays;
- geometry SHA-256
  `43f357d7c085438391b18de46e812698f84bef2280311ee4a753e4a2b09e34a3`.

These values are not assumed to be eternally correct. A deliberate upstream
correction may change them, but only with a minimized repro, a stated
invariant, deterministic evidence, review of the owning layer, and an
intentional standards update.

## Inspection Workflow

Choose `Reference Terrain` in the editor dock. The Terrain Observatory offers
seven views:

- `Surface` shows the canonical authored material appearance;
- `LOD` separates coarse and fine native buffers;
- `Material` uses high-contrast material-ID colors;
- `Triangles` exposes every native triangle edge;
- `Normals` encodes and draws sampled native normals;
- `Seams` frames all tested same-LOD and mixed-LOD interfaces and transition
  ownership, with failures in red;
- `Density` overlays a movable X, Y, or Z scalar-field slice and sample crosses.

The selected chunk receives an AABB outline. Chunk isolation, chunk bounds,
transition visibility, feature labels, and each diagnostic overlay can be
toggled independently. All view settings are preserved in repro snapshots.

Move the terrain cursor, set the edit radius, and apply `Terrain Dig` or
`Terrain Construct`. `Clear Terrain` restores the canonical field. Run
`Reference Terrain` validation for the full seam, buffer, feature,
determinism, incremental-edit, and seven-view observatory proof.

Four committed terrain images lock the surface, material, seam, and density
presentations by dimensions, nonblank variation, and SHA-256.
