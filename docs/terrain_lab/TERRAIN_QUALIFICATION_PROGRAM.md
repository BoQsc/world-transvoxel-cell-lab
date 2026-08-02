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
`../cell_lab/ROADMAP.md`. The milestones below are separate program work.
Their current evidence-backed states are recorded in this document,
`program_manifest.json`, and `qualification_state.json`.

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

- Gate A: `TQP-01` through `TQP-05` must become `qualified` before a production
  terrain architecture or GPU implementation is selected.
- Gate B: edit-driven production work requires `TQP-07` and `TQP-09` through
  `TQP-13`.
- Gate C: production surface rendering requires `TQP-08`, `TQP-18`, `TQP-21`,
  and `TQP-23`.
- Gate D: large-world production claims require `TQP-06`, `TQP-15`, `TQP-16`,
  `TQP-19`, `TQP-20`, `TQP-22`, `TQP-24`, `TQP-26`, and `TQP-27`.
- Gate E: GPU authority cannot advance until `TQP-34` through `TQP-39` pass
  differential qualification.
- Gate F: production release requires every applicable prerequisite and
  `TQP-40` through `TQP-46`.

## How To Follow This Program

The milestones below are numbered and arranged in ground-up execution order.
Items inside parentheses may proceed in parallel. Arrows between batches are
promotion order: investigation may happen early, but qualification cannot skip
an earlier dependency.

The machine-readable execution_plan.json mirrors the same order. TQP revision
5 deliberately replaces the former domain-grouped identifiers; retained
TQP-D006 records the migration from the previous numbering.

## Phase 1: Qualified Foundations And Reference Semantics

This phase fixes the operating envelope, authority, coordinates,
benchmark rules, resolution behavior, chunk lifecycle, field algebra, material
authority, edit semantics, and long-edit baseline before system behavior builds
on them.

Execution batches: TQP-01 -> (TQP-02, TQP-03, TQP-04) ->
(TQP-05, TQP-06) -> (TQP-07, TQP-08) -> TQP-09 ->
(TQP-10, TQP-11) -> (TQP-12, TQP-13) -> TQP-14.

This phase is complete for its declared reference scopes.

### TQP-01: Operating Envelope

Status: `qualified`. Owner: Terrain Qualification Program. Depends on: none.

Complete when world dimensions, vertical range, smallest important feature,
edit frequency, camera speed, view distance, frame and memory budgets, target
hardware, platforms, multiplayer model, and art direction are measurable.

### TQP-02: Authority And Data Model

Status: `qualified`. Owner: Terrain Qualification Program. Depends on: TQP-01.

Complete when procedural fields, authored data, edit journals, baked density,
material attributes, chunk versions, meshes, collision, and caches each have
one documented authority and lifecycle.

### TQP-03: Coordinate And Precision Standard

Status: `qualified`. Owner: Terrain Qualification Program. Depends on: TQP-01.

Complete when sample-space addressing, chunk ownership, negative rounding,
global/local conversion, floating origin, precision budgets, and CPU/GPU
coordinate equivalence have boundary fixtures.

### TQP-04: Qualification And Benchmark Protocol

Status: `qualified`. Owner: Terrain Qualification Program. Depends on: TQP-01.

Complete when evidence formats, promotion states, hardware metadata, warmups,
sample counts, statistical reporting, baseline changes, and review rules are
machine-readable and tested.

### TQP-05: Resolution And Error Standard

Status: `qualified`. Owner: Terrain Qualification Program. Depends on: TQP-01,
TQP-03.

Complete when every LOD has world-space cell size, preservation requirements,
allowed feature disappearance, field-filtering rules, geometric error, and
screen-space error budgets.

### TQP-06: Chunk Lifecycle

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-02, TQP-03.

Complete when requested, generating, ready, visible, collidable, dirty, stale,
cached, failed, and evicted states have legal transitions and fault fixtures.

### TQP-07: Field Algebra

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: Gate A.

Complete when density sign, isovalue, exact and smooth CSG, gradient sampling,
composition order, finite support, and algebraic properties have independent
fixtures.

### TQP-08: Material Field Contract

Status: `qualified`. Owner: Material and Surface Lab. Depends on: TQP-02,
TQP-05.

Complete when IDs, weights, provenance, deterministic ties, construction
ownership, edit composition, storage, and interpolation semantics are fixed.

### TQP-09: Brush Shape Corpus

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: TQP-05, TQP-07.

Complete when spheres, capsules, swept strokes, rounded boxes, planes, stamps,
and bounded-noise shapes have analytic definitions, resolution limits, visual
references, and performance distributions.

### TQP-10: Digging Standard

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: TQP-07, TQP-09.

Complete when subtraction, continuous strokes, overlaps, tunnel clearance,
chunk boundaries, materials, collision publication, and replay are predictable
across qualified LODs.

### TQP-11: Construction Standard

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: TQP-07, TQP-09.

Complete when addition, overlaps, material provenance, architectural shapes,
surface continuity, support metadata, collision publication, and replay are
predictable.

### TQP-12: Resolvability Envelope

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: TQP-05, TQP-09,
TQP-10, TQP-11.

Complete when minimum radius, wall thickness, clearance, curvature, smoothing
width, and noise frequency are measured at every LOD with pass, degradation,
and intentional-disappearance classifications.

### TQP-13: Edit Journal, Undo, And Compaction

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: TQP-02, TQP-10,
TQP-11.

Complete when ordering, duplicate IDs, cancellation, undo/redo, transactions,
serialization, migration, baking, compaction, and deterministic reconstruction
are proven equivalent.

### TQP-14: Long Edit Soak

Status: `qualified`. Owner: Edit Semantics Lab. Depends on: TQP-04, TQP-12,
TQP-13.

Complete when seeded campaigns containing thousands of edits preserve full
rebuild equivalence, seams, collision agreement, latency budgets, allocation
budgets, and retained-memory budgets.

## Phase 2: Temporal Integrity And Durable Publication

This phase proves that real native workers, versioned publication,
persistence, and concurrent edits cannot publish incoherent terrain state.

Execution batches: (TQP-15, TQP-16) -> TQP-17.

This phase is complete for the declared Godot 4.7.1 Windows x86_64 native
reference scope.

### TQP-15: Scheduling, Versioning, And Publication

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-04, TQP-06.

Complete when job ownership, cancellation, generation numbers, priorities,
atomic publication, stale rejection, and deterministic test scheduling are
proven.

### TQP-16: Persistence, Migration, And Recovery

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-02, TQP-13,
TQP-06.

Complete when base fields, journals, baked bricks, checksums, atomic writes,
crash recovery, corruption, compaction, and schema migrations retain
deterministic world state.

### TQP-17: Concurrent And Temporal Edits

Status: `qualified`. Owner: Edit Semantics Lab and Terrain Systems Lab. Depends
on: TQP-13, TQP-06, TQP-15.

Complete when edits during streaming, LOD changes, saves, collision rebuilds,
worker cancellation, and stale-result arrival cannot publish incoherent state.

## Phase 3: Core Terrain Surface And Systems Qualification

This is the active phase. It closes material appearance, streaming,
large-world coordinates, visibility, collision, observability, visual review,
and large-terrain performance in dependency order.

Execution batches: (TQP-18, TQP-19, TQP-20) ->
(TQP-21, TQP-22) -> (TQP-23, TQP-24) ->
(TQP-25, TQP-26) -> TQP-27.

The current work is exactly TQP-18, TQP-19, and TQP-20. They may be
implemented in parallel, but each is promoted independently only after its
declared evidence passes.

### TQP-18: Material Blending

Status: `implemented`. Owner: Material and Surface Lab. Depends on: TQP-08.

Complete when normalized weights, top-material reduction, categorical
boundaries, transition interpolation, and LOD continuity pass exact and visual
standards.

### TQP-19: Streaming Windows

Status: `implemented`. Owner: Terrain Systems Lab. Depends on: TQP-05, TQP-06,
TQP-15.

Complete when fixed camera paths, hysteresis, LOD movement, prefetch, eviction,
teleportation, edit arrival, and boundary stability meet explicit budgets.

### TQP-20: Large-World Coordinates

Status: `implemented`. Owner: Terrain Systems Lab. Depends on: TQP-03, TQP-06.

Complete when origin shifts, distant edits, negative coordinates, save
coordinates, long traversal, and CPU/GPU precision remain stable.

### TQP-21: Texture System

Status: `implemented`. Owner: Material and Surface Lab. Depends on: TQP-08,
TQP-18.

Complete when texture arrays, world-space triplanar mapping, scale, mipmaps,
anisotropy, normal maps, caves, cliffs, and edited surfaces remain continuous
within performance budgets.

### TQP-22: Visibility And Residency

Status: `implemented`. Owner: Terrain Systems Lab and Material and Surface Lab.
Depends on: TQP-05, TQP-19, TQP-20.

Complete when culling, occlusion, LOD/HLOD policy, draw counts, buffer
residency, distant representation, and memory budgets are observable and
qualified.

### TQP-23: Surface Shading

Status: `implemented`. Owner: Material and Surface Lab. Depends on: TQP-21.

Complete when normals, tangents, slope and height masks, lighting, decals,
wetness, precision, and camera-distance behavior pass fixed and temporal
inspection.

### TQP-24: Collision, Queries, And Navigation

Status: `implemented`. Owner: Terrain Systems Lab. Depends on: TQP-06, TQP-15,
TQP-16.

Complete when render meshes, physics shapes, field queries, raycasts, navmesh
updates, and publication versions agree during edits and streaming.

### TQP-25: Visual Quality Corpus

Status: `specified`. Owner: Material and Surface Lab. Depends on: TQP-05,
TQP-18, TQP-21, TQP-23.

Complete when natural, constructed, destroyed, and adversarial terrain scenes
have art-direction targets, fixed cameras, videos, automated comparisons, and
recorded human acceptance.

### TQP-26: Terrain Observatory

Status: `implemented`. Owner: Terrain Systems Lab. Depends on: TQP-06, TQP-15,
TQP-16, TQP-19, TQP-20, TQP-22, TQP-24.

Complete when chunk state, jobs, versions, LOD decisions, edit dependencies,
buffers, memory, timings, collision state, and rejection reasons can be
inspected and exported as repros.

### TQP-27: Large-Terrain Performance And Soak

Status: `implemented`. Owner: Terrain Systems Lab. Depends on: TQP-04, TQP-16,
TQP-19, TQP-20, TQP-22, TQP-24, TQP-26.

Complete when fixed traversal, teleportation, editing, save/load, and failure
scenarios pass frame-time, throughput, memory, hitch, and long-duration
budgets.

## Phase 4: Destruction And Structural World Systems

This phase qualifies destructive edits and optional world systems only
after the core edit, persistence, streaming, material, and collision contracts
they consume are stable.

Execution batches: (TQP-28, TQP-29, TQP-30, TQP-31, TQP-32) ->
TQP-33.

Reference behavior exists, but these milestones remain unqualified until their
native, temporal, persistence, visual, and performance gaps close.

### TQP-28: Explosion Corpus

Status: `implemented`. Owner: Edit Semantics Lab and Structural Systems Lab.
Depends on: TQP-09, TQP-10, TQP-11, TQP-12, TQP-13, TQP-14, TQP-17.

Complete when radial and directed blasts, material damage, bounded noise,
overlap, fragmentation inputs, collision timing, replay, and cost are
qualified.

### TQP-29: Connectivity And Support

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
TQP-02, TQP-11, TQP-12.

Complete when anchors, solid connectivity, support graphs, floating terrain,
material strength, and under-resolved supports have deterministic policies.

### TQP-30: Fluids And Hydrology

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
TQP-05, TQP-16, TQP-19.

Complete when terrain-water intersections, coastlines, caves, drainage,
flooding, edits, LODs, persistence, and rendering have defined ownership.

### TQP-31: Vegetation And Object Placement

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
TQP-08, TQP-16, TQP-19.

Complete when placement provenance, invalidation, regeneration, persistence,
collision, and destruction after terrain edits are deterministic.

### TQP-32: Roads, Structures, And Authored Terrain

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
TQP-08, TQP-11, TQP-16.

Complete when stamps, foundations, tunnels, bridges, authored construction,
procedural fields, edits, materials, and LODs compose predictably.

### TQP-33: Collapse And Debris

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
TQP-24, TQP-28, TQP-29.

Complete when separated components, collapse decisions, rigid-body conversion,
remeshing, collision, cleanup, persistence, and replay are qualified.

## Phase 5: GPU Candidate Qualification

This phase evaluates GPU acceleration against the qualified CPU
reference. It does not replace CPU authority or begin by rewriting the lab.

Execution batches: TQP-34 -> TQP-35 -> TQP-36 ->
(TQP-37, TQP-38) -> TQP-39.

TQP-34 is specified. Later batches remain blocked until concrete GPU field,
meshing, residency, and multi-vendor hardware targets exist.

### TQP-34: GPU Architecture Decision

Status: `specified`. Owner: Backend Qualification Lab. Depends on: Gate A.

Complete when field evaluation, meshing, buffer residency, rendering,
collision readback, synchronization, target APIs, and expected benefit are
separate measured decisions.

### TQP-35: GPU Field Evaluation

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-07,
TQP-08, TQP-12, TQP-34.

Complete when GPU density, gradients, materials, edits, filtering, precision,
and determinism pass analytical and CPU differential evidence.

### TQP-36: GPU Meshing Candidate

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-34,
TQP-35.

Complete when GPU regular, transition, and chunk extraction exists as a
candidate without weakening or replacing the native CPU reference.

### TQP-37: CPU/GPU Differential Corpus

Status: `blocked`. Owner: Backend Qualification Lab and Cell Lab. Depends on:
TQP-36.

Complete when topology, seams, feature survival, materials, edits, bounds, and
numeric tolerances pass the shared primitive and terrain corpora.

### TQP-38: GPU Residency And Publication

Status: `blocked`. Owner: Backend Qualification Lab and Terrain Systems Lab.
Depends on: TQP-15, TQP-22, TQP-36.

Complete when allocation, reuse, indirect drawing, transfer, collision
readback, stale work, synchronization, and device-loss recovery are qualified.

### TQP-39: Cross-Hardware GPU Matrix

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-04,
TQP-37, TQP-38.

Complete when correctness, reproducibility, performance, memory, drivers,
vendors, graphics APIs, and explicitly unsupported hardware are recorded.

## Phase 6: Production Terrain And Release Qualification

This phase begins only with a pinned production terrain candidate and
qualified prerequisite gates. It proves the addon boundary, authoring,
networking when applicable, integration-game parity, release matrix, and
long-haul behavior before publishing Standard 1.0.

Execution batches: TQP-40 -> (TQP-41, TQP-42) -> TQP-43 ->
TQP-44 -> TQP-45 -> TQP-46.

This phase is blocked because a pinned candidate production addon and its later
release evidence do not yet exist.

### TQP-40: Production Addon Boundary

Status: `blocked`. Owner: `world-transvoxel-terrain`. Depends on: Gates A
through D.

Complete when runtime APIs, data ownership, dependencies, configuration,
extension points, threading, errors, and unsupported behavior are frozen for a
candidate release.

### TQP-41: Authoring And Inspection Workflow

Status: `blocked`. Owner: `world-transvoxel-terrain`. Depends on: TQP-08,
TQP-10, TQP-11, TQP-12, TQP-13, TQP-14, TQP-17, TQP-18, TQP-21, TQP-23,
TQP-25, TQP-26, TQP-28, TQP-40.

Complete when brushes, previews, undo/redo, material authoring, diagnostics,
imports, profiling, and one-action repro export support real workflows.

### TQP-42: Networking And Recovery

Status: `blocked`. Owner: Production terrain and integration layers. Depends
on: TQP-13, TQP-16, TQP-17, TQP-40.

Complete when replication, ordering, conflict resolution, late join, save
recovery, disconnects, corruption, and authority transitions are qualified for
the declared multiplayer model.

### TQP-43: Integration-Game Parity

Status: `blocked`. Owner: Integration game and `world-transvoxel-terrain`.
Depends on: TQP-27, TQP-40, TQP-41.

Complete when representative gameplay terrain, edits, saves, rendering,
collision, and failures reduce to canonical qualification evidence.

### TQP-44: Production Release Matrix

Status: `blocked`. Owner: Terrain Qualification Program. Depends on:
applicable TQP-01 through TQP-43 milestones.

Complete when supported platforms, renderers, native artifacts, hardware,
upgrade paths, visuals, performance budgets, and explicitly unqualified scope
form a reproducible release bundle.

### TQP-45: Long-Haul Certification

Status: `blocked`. Owner: Terrain Qualification Program. Depends on: TQP-44.

Complete when extended traversal, editing, construction, destruction,
save/load, streaming, origin shifting, device events, and fault injection pass
without correctness, memory, or performance drift.

### TQP-46: Production Terrain Standard 1.0

Status: `blocked`. Owner: Terrain Qualification Program. Depends on: TQP-45.

Complete when the final evidence bundle is reviewed, versioned, reproducible,
and explicit about every qualified and unqualified claim. This milestone marks
a standard, not an assertion that future terrain work is finished.

## Current Program State

The program has executed every milestone to a truthful evidence state:

- `TQP-01` through `TQP-17` are qualified
  for their narrow contract, native Windows reference, or reference-model
  scopes. Gate B is qualified; its native chunk rebuild benchmark remains a
  background/debug reference and is not a production frame-time claim.
- `TQP-18` through `TQP-24` and `TQP-26` through `TQP-33` have implemented
  reference behavior but
  still lack one or more exit criteria named in their milestone contracts.
- `TQP-25` and `TQP-34` are specified. The former requires human visual
  acceptance; the latter requires measured GPU-candidate benefit.
- `TQP-35` through `TQP-46` are blocked by named external targets and exit
  conditions in `program_blockers.json`.

The next dependency-ordered work is TQP-18 material blending, TQP-19 streaming
windows, and TQP-20 large-world coordinates. These are independent entries in
the first step of `TQP-WAVE-02`.
Production and GPU claims remain closed. A blocked milestone may advance only
when its recorded exit condition exists and the required evidence passes.

## Decision Log

Program decisions must record:

- date and decision identifier;
- affected milestones and repositories;
- alternatives considered;
- evidence used;
- qualified and unqualified scope;
- standards or baselines changed;
- review and downstream impact.

Retained decisions:

- `TQP-D001`: preserve the Cell Lab as the foundational native meshing
  qualification system and place production-terrain research in separately
  owned program milestones.
- `TQP-D002`: execute the complete program in dependency order and fail closed
  rather than inferring unavailable evidence.
- `TQP-D003`: retain `world-transvoxel` CPU meshing as authority and keep GPU
  field, meshing, residency, and readback as separate candidate promotions.
- `TQP-D004`: qualify the Gate B native edit corpus and long-edit reference
  workload without claiming production frame-time performance.
- `TQP-D005`: qualify TQP-15, TQP-16, and TQP-17 for the retained native
  Windows temporal-integrity and persistence reference scope.
- `TQP-D006`: replace domain-grouped identifiers with the ground-up TQP-01
  through TQP-46 execution sequence without changing milestone evidence state.
