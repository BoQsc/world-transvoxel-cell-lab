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
- a cylindrical tunnel carved through solid terrain;
- an ellipsoidal overhang shelf unioned above the base surface;
- a thin box-shaped vertical feature;
- deterministic material regions.

Six signed-density probes permanently verify bedrock, open air, tunnel air,
overhang solid, thin-feature solid, and adjacent thin-feature clearance.

## Required Invariants

A passing result requires:

- all 12 chunks mesh successfully through the native production path;
- all native indices, normals, and materials satisfy buffer contracts;
- no native buffer has nonmanifold edges or orientation conflicts;
- all 12 same-LOD neighbor seam signatures match;
- all four LOD1-to-LOD0 interface signatures match;
- visible crack count is zero;
- repeated full builds produce the same geometry signature;
- all six field feature probes match;
- cross-chunk dig and construct edits change only affected chunks;
- partial dirty-chunk rebuild output exactly matches full rebuild output;
- all seams still match after each edit.

## Locked Baseline

The committed standard currently requires:

- 12 chunks: eight LOD1 and four LOD0;
- four chunks with transition surfaces;
- 113,705 native sample calls;
- 9,162 regular triangles;
- 252 transition triangles;
- 9,414 total triangles;
- material IDs `1`, `2`, and `4`;
- geometry SHA-256
  `10cceefa944d4ebf8b73877ef8ebe1032a42cf89ef7fe3d43c60a6f469d98fa8`.

These values are not assumed to be eternally correct. A deliberate upstream
correction may change them, but only with a minimized repro, a stated
invariant, deterministic evidence, review of the owning layer, and an
intentional standards update.

## Inspection Workflow

Choose `Reference Terrain` in the editor dock. The view colors coarse chunks,
fine chunks, and transition surfaces separately. The selected chunk receives a
strong wire outline; optional bounds expose the complete LOD layout.

Move the terrain cursor, set the edit radius, and apply `Terrain Dig` or
`Terrain Construct`. `Clear Terrain` restores the canonical field. Run
`Reference Terrain` validation for the full seam, buffer, feature,
determinism, and incremental-edit proof.
