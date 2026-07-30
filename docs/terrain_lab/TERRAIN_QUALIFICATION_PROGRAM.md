# Terrain Qualification Program

## Purpose

The Terrain Qualification Program (`TQP`) defines the work required to move
from a qualified Transvoxel meshing primitive to a qualified production terrain
system.

This is a cross-project program charter owned by the separate
`world_transvoxel_terrain_lab` addon inside the World Transvoxel Labs
monorepo. Its location does not give Terrain Lab ownership over production
implementation or over the `world_transvoxel_cell_lab` addon.

Cell Lab milestones 1 through 29 remain complete and closed in
`../cell_lab/ROADMAP.md`. The milestones below are new program work. All begin
with status `proposed`.

## Authority Chain

```text
field, edit, coordinate, and resolution contracts
    -> world-transvoxel native meshing authority
        -> Cell Lab meshing qualification
            -> edit and surface qualification
                -> terrain-system qualification
                    -> gameplay and production qualification
```

`world-transvoxel` is the production meshing dependency. The Cell Lab is a
development and CI qualification dependency. A production terrain runtime must
not depend on Cell Lab scene state, editor controls, or report presentation.

The CPU native backend remains the pinned meshing reference while GPU work is
experimental. A GPU implementation must qualify as a candidate against shared
contracts and evidence before any authority claim changes.

## Project Ownership

| Project or lab | Responsibility |
| --- | --- |
| `world-transvoxel` | Native regular-cell, transition-cell, and chunk meshing implementation |
| `world_transvoxel_cell_lab` addon | Primitive conformance, minimized repros, topology, seams, deterministic fixtures, and controlled microbenchmarks |
| Edit Semantics Lab | Density algebra, digging, construction, brush behavior, edit history, resolvability, and explosions |
| Material and Surface Lab | Material fields, blending, textures, shading, LOD continuity, and visual-quality evidence |
| Terrain Systems Lab | Chunk lifecycle, jobs, streaming, persistence, collision synchronization, observability, and large-world performance |
| Structural and World Systems Lab | Support, collapse, debris, fluids, vegetation, roads, and authored structures |
| Backend Qualification Lab | CPU/GPU differential correctness, GPU residency, synchronization, portability, and throughput |
| `world-transvoxel-terrain` | Candidate production terrain runtime; ownership is earned milestone by milestone |
| Integration game | Downstream gameplay proof and source of reducible production failures |

Names for new labs describe domain ownership inside
`world_transvoxel_terrain_lab`, not additional repositories or dependencies.
Their contracts, fixtures, reports, and promotion states remain separate.

## Cell Lab Freeze Boundary

New work belongs in the Cell Lab only when it does at least one of the
following:

- strengthens a native meshing invariant;
- adds a minimized deterministic backend repro;
- expands a controlled cell, transition, chunk, seam, or field corpus;
- improves primitive-level observability or measurement;
- retains evidence for an upstream correction;
- qualifies a candidate backend against the same primitive contract.

Production chunk management, streaming, authoring UX, texture systems,
destruction policy, gameplay, and world persistence do not belong in the
`world_transvoxel_cell_lab` addon or its root node.

## Milestone Status

| Status | Meaning |
| --- | --- |
| `proposed` | Scope is recorded but its contract and evidence are not accepted |
| `specified` | Contract, ownership, fixtures, and exit criteria are reviewed |
| `implemented` | Candidate behavior exists but qualification is incomplete |
| `qualified` | Required evidence passes for an explicitly declared scope |
| `production` | Qualified behavior is integrated, supported, monitored, and releasable |
| `blocked` | A named external dependency prevents meaningful progress |

Code existence alone cannot advance a milestone to `qualified`. Unsupported
platforms, renderers, workloads, and scales must remain explicitly
unqualified.

## Evidence Standard

Each milestone must identify which evidence classes it requires:

- a written behavioral contract and ownership boundary;
- deterministic positive, boundary, and retained negative fixtures;
- an independent invariant or reference where self-validation is possible;
- machine-readable results and stable repro export;
- automated regression coverage;
- visual or temporal evidence when appearance changes;
- repeated performance distributions when cost is part of the claim;
- dependency, build, platform, renderer, hardware, and driver provenance;
- declared qualified and explicitly unqualified scope;
- downstream parity when production behavior is affected.

Performance evidence requires warmup policy, sample count, p50, p95, p99,
worst-case latency, retained and peak memory, build type, machine metadata, and
the exact workload signature. A single average timing is not qualification.

Visual quality evidence is distinct from geometric correctness. Pleasantness
requires an art-direction target, fixed comparisons, temporal inspection, and
human review in addition to automated checks.

## Program Gates

- Gate A: `TQP-01` through `TQP-05` must become `specified` before a production
  terrain architecture or GPU implementation is selected.
- Gate B: edit-driven production work requires `TQP-06` through `TQP-11`.
- Gate C: production surface rendering requires `TQP-15` through `TQP-18`.
- Gate D: large-world production claims require `TQP-20` through `TQP-28`.
- Gate E: GPU authority cannot advance until `TQP-34` through `TQP-39` pass
  differential qualification.
- Gate F: production release requires every applicable prerequisite and
  `TQP-40` through `TQP-46`.

## Foundation

### TQP-01: Operating Envelope

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: none.

Complete when world dimensions, vertical range, smallest important feature,
edit frequency, camera speed, view distance, frame and memory budgets, target
hardware, platforms, multiplayer model, and art direction are measurable.

### TQP-02: Authority And Data Model

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-01.

Complete when procedural fields, authored data, edit journals, baked density,
material attributes, chunk versions, meshes, collision, and caches each have
one documented authority and lifecycle.

### TQP-03: Coordinate And Precision Standard

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-01.

Complete when sample-space addressing, chunk ownership, negative rounding,
global/local conversion, floating origin, precision budgets, and CPU/GPU
coordinate equivalence have boundary fixtures.

### TQP-04: Resolution And Error Standard

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-01,
TQP-03.

Complete when every LOD has world-space cell size, preservation requirements,
allowed feature disappearance, field-filtering rules, geometric error, and
screen-space error budgets.

### TQP-05: Qualification And Benchmark Protocol

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-01.

Complete when evidence formats, promotion states, hardware metadata, warmups,
sample counts, statistical reporting, baseline changes, and review rules are
machine-readable and tested.

## Edit Semantics Lab

### TQP-06: Field Algebra

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: Gate A.

Complete when density sign, isovalue, exact and smooth CSG, gradient sampling,
composition order, finite support, and algebraic properties have independent
fixtures.

### TQP-07: Brush Shape Corpus

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: TQP-04, TQP-06.

Complete when spheres, capsules, swept strokes, rounded boxes, planes, stamps,
and bounded-noise shapes have analytic definitions, resolution limits, visual
references, and performance distributions.

### TQP-08: Digging Standard

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: TQP-06, TQP-07.

Complete when subtraction, continuous strokes, overlaps, tunnel clearance,
chunk boundaries, materials, collision publication, and replay are predictable
across qualified LODs.

### TQP-09: Construction Standard

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: TQP-06, TQP-07.

Complete when addition, overlaps, material provenance, architectural shapes,
surface continuity, support metadata, collision publication, and replay are
predictable.

### TQP-10: Resolvability Envelope

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: TQP-04, TQP-07,
TQP-08, TQP-09.

Complete when minimum radius, wall thickness, clearance, curvature, smoothing
width, and noise frequency are measured at every LOD with pass, degradation,
and intentional-disappearance classifications.

### TQP-11: Edit Journal, Undo, And Compaction

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: TQP-02, TQP-08,
TQP-09.

Complete when ordering, duplicate IDs, cancellation, undo/redo, transactions,
serialization, migration, baking, compaction, and deterministic reconstruction
are proven equivalent.

### TQP-12: Long Edit Soak

Status: `proposed`. Owner: Edit Semantics Lab. Depends on: TQP-05, TQP-10,
TQP-11.

Complete when seeded campaigns containing thousands of edits preserve full
rebuild equivalence, seams, collision agreement, latency budgets, allocation
budgets, and retained-memory budgets.

### TQP-13: Concurrent And Temporal Edits

Status: `proposed`. Owner: Edit Semantics Lab and Terrain Systems Lab. Depends
on: TQP-11, TQP-20, TQP-21.

Complete when edits during streaming, LOD changes, saves, collision rebuilds,
worker cancellation, and stale-result arrival cannot publish incoherent state.

### TQP-14: Explosion Corpus

Status: `proposed`. Owner: Edit Semantics Lab and Structural Systems Lab.
Depends on: TQP-07 through TQP-13.

Complete when radial and directed blasts, material damage, bounded noise,
overlap, fragmentation inputs, collision timing, replay, and cost are
qualified.

## Material And Surface Lab

### TQP-15: Material Field Contract

Status: `proposed`. Owner: Material and Surface Lab. Depends on: TQP-02,
TQP-04.

Complete when IDs, weights, provenance, deterministic ties, construction
ownership, edit composition, storage, and interpolation semantics are fixed.

### TQP-16: Material Blending

Status: `proposed`. Owner: Material and Surface Lab. Depends on: TQP-15.

Complete when normalized weights, top-material reduction, categorical
boundaries, transition interpolation, and LOD continuity pass exact and visual
standards.

### TQP-17: Texture System

Status: `proposed`. Owner: Material and Surface Lab. Depends on: TQP-15,
TQP-16.

Complete when texture arrays, world-space triplanar mapping, scale, mipmaps,
anisotropy, normal maps, caves, cliffs, and edited surfaces remain continuous
within performance budgets.

### TQP-18: Surface Shading

Status: `proposed`. Owner: Material and Surface Lab. Depends on: TQP-17.

Complete when normals, tangents, slope and height masks, lighting, decals,
wetness, precision, and camera-distance behavior pass fixed and temporal
inspection.

### TQP-19: Visual Quality Corpus

Status: `proposed`. Owner: Material and Surface Lab. Depends on: TQP-04,
TQP-16 through TQP-18.

Complete when natural, constructed, destroyed, and adversarial terrain scenes
have art-direction targets, fixed cameras, videos, automated comparisons, and
recorded human acceptance.

## Terrain Systems Lab

### TQP-20: Chunk Lifecycle

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-02, TQP-03.

Complete when requested, generating, ready, visible, collidable, dirty, stale,
cached, failed, and evicted states have legal transitions and fault fixtures.

### TQP-21: Scheduling, Versioning, And Publication

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-05, TQP-20.

Complete when job ownership, cancellation, generation numbers, priorities,
atomic publication, stale rejection, and deterministic test scheduling are
proven.

### TQP-22: Streaming Windows

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-04, TQP-20,
TQP-21.

Complete when fixed camera paths, hysteresis, LOD movement, prefetch, eviction,
teleportation, edit arrival, and boundary stability meet explicit budgets.

### TQP-23: Large-World Coordinates

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-03, TQP-20.

Complete when origin shifts, distant edits, negative coordinates, save
coordinates, long traversal, and CPU/GPU precision remain stable.

### TQP-24: Visibility And Residency

Status: `proposed`. Owner: Terrain Systems Lab and Material and Surface Lab.
Depends on: TQP-04, TQP-22, TQP-23.

Complete when culling, occlusion, LOD/HLOD policy, draw counts, buffer
residency, distant representation, and memory budgets are observable and
qualified.

### TQP-25: Persistence, Migration, And Recovery

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-02, TQP-11,
TQP-20.

Complete when base fields, journals, baked bricks, checksums, atomic writes,
crash recovery, corruption, compaction, and schema migrations retain
deterministic world state.

### TQP-26: Collision, Queries, And Navigation

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-20, TQP-21,
TQP-25.

Complete when render meshes, physics shapes, field queries, raycasts, navmesh
updates, and publication versions agree during edits and streaming.

### TQP-27: Terrain Observatory

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-20 through
TQP-26.

Complete when chunk state, jobs, versions, LOD decisions, edit dependencies,
buffers, memory, timings, collision state, and rejection reasons can be
inspected and exported as repros.

### TQP-28: Large-Terrain Performance And Soak

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-05, TQP-22
through TQP-27.

Complete when fixed traversal, teleportation, editing, save/load, and failure
scenarios pass frame-time, throughput, memory, hitch, and long-duration
budgets.

## Structural And World Systems Lab

### TQP-29: Connectivity And Support

Status: `proposed`. Owner: Structural and World Systems Lab. Depends on:
TQP-02, TQP-09, TQP-10.

Complete when anchors, solid connectivity, support graphs, floating terrain,
material strength, and under-resolved supports have deterministic policies.

### TQP-30: Collapse And Debris

Status: `proposed`. Owner: Structural and World Systems Lab. Depends on:
TQP-14, TQP-26, TQP-29.

Complete when separated components, collapse decisions, rigid-body conversion,
remeshing, collision, cleanup, persistence, and replay are qualified.

### TQP-31: Fluids And Hydrology

Status: `proposed`. Owner: Structural and World Systems Lab. Depends on:
TQP-04, TQP-22, TQP-25.

Complete when terrain-water intersections, coastlines, caves, drainage,
flooding, edits, LODs, persistence, and rendering have defined ownership.

### TQP-32: Vegetation And Object Placement

Status: `proposed`. Owner: Structural and World Systems Lab. Depends on:
TQP-15, TQP-22, TQP-25.

Complete when placement provenance, invalidation, regeneration, persistence,
collision, and destruction after terrain edits are deterministic.

### TQP-33: Roads, Structures, And Authored Terrain

Status: `proposed`. Owner: Structural and World Systems Lab. Depends on:
TQP-09, TQP-15, TQP-25.

Complete when stamps, foundations, tunnels, bridges, authored construction,
procedural fields, edits, materials, and LODs compose predictably.

## Backend Qualification Lab

### TQP-34: GPU Architecture Decision

Status: `proposed`. Owner: Backend Qualification Lab. Depends on: Gate A.

Complete when field evaluation, meshing, buffer residency, rendering,
collision readback, synchronization, target APIs, and expected benefit are
separate measured decisions.

### TQP-35: GPU Field Evaluation

Status: `proposed`. Owner: Backend Qualification Lab. Depends on: TQP-06,
TQP-10, TQP-15, TQP-34.

Complete when GPU density, gradients, materials, edits, filtering, precision,
and determinism pass analytical and CPU differential evidence.

### TQP-36: GPU Meshing Candidate

Status: `proposed`. Owner: Backend Qualification Lab. Depends on: TQP-34,
TQP-35.

Complete when GPU regular, transition, and chunk extraction exists as a
candidate without weakening or replacing the native CPU reference.

### TQP-37: CPU/GPU Differential Corpus

Status: `proposed`. Owner: Backend Qualification Lab and Cell Lab. Depends on:
TQP-36.

Complete when topology, seams, feature survival, materials, edits, bounds, and
numeric tolerances pass the shared primitive and terrain corpora.

### TQP-38: GPU Residency And Publication

Status: `proposed`. Owner: Backend Qualification Lab and Terrain Systems Lab.
Depends on: TQP-21, TQP-24, TQP-36.

Complete when allocation, reuse, indirect drawing, transfer, collision
readback, stale work, synchronization, and device-loss recovery are qualified.

### TQP-39: Cross-Hardware GPU Matrix

Status: `proposed`. Owner: Backend Qualification Lab. Depends on: TQP-05,
TQP-37, TQP-38.

Complete when correctness, reproducibility, performance, memory, drivers,
vendors, graphics APIs, and explicitly unsupported hardware are recorded.

## Production Qualification

### TQP-40: Production Addon Boundary

Status: `proposed`. Owner: `world-transvoxel-terrain`. Depends on: Gates A
through D.

Complete when runtime APIs, data ownership, dependencies, configuration,
extension points, threading, errors, and unsupported behavior are frozen for a
candidate release.

### TQP-41: Authoring And Inspection Workflow

Status: `proposed`. Owner: `world-transvoxel-terrain`. Depends on: TQP-08
through TQP-19, TQP-27, TQP-40.

Complete when brushes, previews, undo/redo, material authoring, diagnostics,
imports, profiling, and one-action repro export support real workflows.

### TQP-42: Integration-Game Parity

Status: `proposed`. Owner: Integration game and `world-transvoxel-terrain`.
Depends on: TQP-28, TQP-40, TQP-41.

Complete when representative gameplay terrain, edits, saves, rendering,
collision, and failures reduce to canonical qualification evidence.

### TQP-43: Networking And Recovery

Status: `proposed`. Owner: Production terrain and integration layers. Depends
on: TQP-11, TQP-13, TQP-25, TQP-40.

Complete when replication, ordering, conflict resolution, late join, save
recovery, disconnects, corruption, and authority transitions are qualified for
the declared multiplayer model.

### TQP-44: Production Release Matrix

Status: `proposed`. Owner: Terrain Qualification Program. Depends on:
applicable TQP-01 through TQP-43 milestones.

Complete when supported platforms, renderers, native artifacts, hardware,
upgrade paths, visuals, performance budgets, and explicitly unqualified scope
form a reproducible release bundle.

### TQP-45: Long-Haul Certification

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-44.

Complete when extended traversal, editing, construction, destruction,
save/load, streaming, origin shifting, device events, and fault injection pass
without correctness, memory, or performance drift.

### TQP-46: Production Terrain Standard 1.0

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-45.

Complete when the final evidence bundle is reviewed, versioned, reproducible,
and explicit about every qualified and unqualified claim. This milestone marks
a standard, not an assertion that future terrain work is finished.

## Immediate Work

Only Gate A is authorized as the next program phase:

1. Specify `TQP-01` operating envelope.
2. Specify `TQP-02` authority and data model.
3. Specify `TQP-03` coordinate and precision standard.
4. Specify `TQP-04` resolution and error standard.
5. Specify `TQP-05` qualification and benchmark protocol.

No production rewrite or GPU-primary architecture should be selected before
those five specifications produce measurable requirements.

## Decision Log

Program decisions must record:

- date and decision identifier;
- affected milestones and repositories;
- alternatives considered;
- evidence used;
- qualified and unqualified scope;
- standards or baselines changed;
- review and downstream impact.

The initial decision is `TQP-D001`: preserve the Cell Lab as the foundational
native meshing qualification system and place production-terrain research in
separately owned program milestones.
