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
                -> bounded terrain-system qualification
                    -> native adaptive-terrain qualification
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
- Gate D: bounded large-world reference claims require `TQP-06`, `TQP-15`,
  `TQP-16`, `TQP-19`, `TQP-20`, `TQP-22`, `TQP-24`, `TQP-26`, and `TQP-27`.
- Gate E: native adaptive-terrain authority requires `TQP-28` through
  `TQP-45`. Gate D's bounded reference models do not satisfy this gate.
- Gate F: GPU authority cannot advance until `TQP-52` through `TQP-57` pass
  differential qualification against Gate E.
- Gate G: production release requires every applicable prerequisite and
  `TQP-58` through `TQP-64`.

## How To Follow This Program

The milestones below are numbered and arranged in ground-up execution order.
Items inside parentheses may proceed in parallel. Arrows between batches are
promotion order: investigation may happen early, but qualification cannot skip
an earlier dependency.

The machine-readable `execution_plan.json` mirrors the same order but is not a
second human roadmap. Program revision 25 preserves the ground-up sequence
introduced by `TQP-D017` and advances only milestones with retained evidence.
The older revision-5 migration remains retained in `TQP-D006` as history.

## Completeness And Claim Boundary

Qualification is not transitive across a wider field, LOD arrangement,
residency shape, edit history, or runtime scale. In particular:

- Cell Lab primitive conformance does not by itself prove assembled terrain;
- a flat or gently varying native window does not exercise the complex field
  and transition topology needed by terrain;
- sampling edits independently at LOD0 through LOD7 does not prove an edit
  crossing active LOD boundaries;
- a large catalog with a small resident window does not prove a large,
  vertically layered adaptive terrain workload;
- one renderer, camera path, machine, or accepted visual corpus does not prove
  production visual quality;
- passing self-consistency checks is not enough where an independent oracle or
  differential corpus can be built.

The 2026-08-02 terrain-core completeness audit found the former roadmap moved
from bounded TQP-27 evidence directly to destruction. Phase 4 closes that gap.
Until Gate E passes, this program may claim the qualified TQP-01 through TQP-33
scopes, but it must not claim authoritative dynamic adaptive Transvoxel terrain.

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

## Phase 3: Bounded Terrain Surface And Systems Qualification

This phase established bounded material appearance, streaming, large-world
coordinates, visibility, collision, observability, visual review, and
large-terrain performance references. Its qualified results are prerequisites,
not a substitute for the native adaptive-terrain evidence in Phase 4.

Execution batches: (TQP-18, TQP-19, TQP-20) ->
(TQP-21, TQP-22) -> (TQP-23, TQP-24) ->
(TQP-25, TQP-26) -> TQP-27.

TQP-18 through TQP-27 are qualified for their declared reference scopes.
TQP-21 closed after the corrected deterministic Forward+/D3D12 observatory
render received explicit human acceptance in `TQP-D013`. TQP-23 then closed
for its bounded reference surface-shading scope through `TQP-D014`. TQP-25
closed through `TQP-D015` after complete human review of its four fixtures,
motion cycles, and adversarial shadow controls; `TQP-F001` is closed only for
that declared Windows reference scope. TQP-26 is qualified for its diagnostic
and repro-export scope. TQP-27 is qualified through `TQP-D016` for its bounded
native Windows 2K-world performance and durability scope. `TQP-F002` keeps
large-volume snapshot compaction open while durable edit-journal restart is the
qualified persistence path.

### TQP-18: Material Blending

Status: `qualified` for the deterministic reference material-blending scope.
Owner: Material and Surface Lab. Depends on: TQP-08.

Complete when normalized weights, top-material reduction, categorical
boundaries, transition interpolation, and LOD continuity pass exact and visual
standards.

### TQP-19: Streaming Windows

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-05, TQP-06,
TQP-15.

Qualified for the deterministic horizontal single-layer reference model after
fixed paths, hysteresis,
LOD movement, prefetch, eviction, teleportation, edit arrival, boundary
stability, residency limits, and retained debug performance distributions pass.
Vertical multi-layer streaming, production terrain residency, and asynchronous
native generation remain explicitly unqualified.

### TQP-20: Large-World Coordinates

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-03, TQP-06.

Qualified for the CPU large-world reference after origin shifts, distant edits,
negative coordinates, decimal-string save coordinates, origin-relative render
conversion, and 100,000 traversal steps pass without integer drift. GPU
equivalence remains explicitly unqualified until TQP-53 through TQP-57.

### TQP-21: Texture System

Status: `qualified` for the accepted Windows reference texture-system scope.
Owner: Material and Surface Lab. Depends on: TQP-08, TQP-18.

The 80-fixture CPU contract covers texture arrays, floating-origin compensated
world-space triplanar coordinates, mipmaps, anisotropy, normal reorientation,
and shared-position continuity at LOD0-7. The 3x3x2 observatory fixture now
applies the qualified 0.5 m sample scale, renders both vertical layers needed
for dug surfaces, compares all 33 adjacent same-LOD chunk pairs, and requires
zero errors across its 27 surface-bearing interfaces. It also merges all regular
triangles into an independent finite-window edge audit that requires zero
interior openings and zero non-manifold edges, with an injected-hole negative
control. Full, tangent-seam, and tangent-pole captures are byte-identical across
cold/warm runs. `TQP-D011` retains the first pairwise tangent-seam correction;
`TQP-D012` records the later assembled-topology false negative and exact-
isovalue endpoint correction; `TQP-D013` records explicit acceptance of the
corrected reference render. Production assets, GPU cost, and cross-GPU
equivalence remain open.

### TQP-22: Visibility And Residency

Status: `qualified` for the deterministic horizontal CPU reference. Owner:
Terrain Systems Lab and Material and Surface Lab. Depends on: TQP-05, TQP-19,
TQP-20.

Qualified behavior includes fixed-view frustum and conservative angular
occlusion, LOD and HLOD selection, reference draw and retained-buffer
accounting, origin-shift and teleport invariance, and stale edit-buffer
rejection. Vertical multi-layer residency, Godot renderer occlusion, real GPU
submission, production HLOD geometry, and production budgets remain
explicitly unqualified.

### TQP-23: Surface Shading

Status: `qualified` for the bounded Windows reference surface-shading scope.
Owner: Material and Surface Lab. Depends on: TQP-21.

The separate reference shader now passes analytical normals, stable tangents,
slope and global-height masks, wetness, projected decal, origin precision, and
camera-distance contracts. Retained near/far Forward+/Vulkan captures each use
two cold/warm instances with eight byte-identical measured frames. A separate
`@tool` review scene now drives the same native fixture through a deterministic
near/far motion path and ten lit or diagnostic views. Eight named criteria
cover world anchoring, temporal flicker, triplanar transitions, detail fade,
normal response, mask attachment, visible shading discontinuities, and
world-anchored cast shadows. The shadow-isolation mode uses constant material
response, and an on/off sun-shadow comparison separates renderer shadows from
surface texture and normal behavior. A candidate pass requires every criterion,
both shadow states, every diagnostic, and two complete motion cycles;
uncertainty remains pending, and the scene writes only a non-authoritative
`user://` draft. The guided review uses a finer `0.25 m` native fixture while
the accepted Observatory baseline remains `0.5 m`; cast-shadow silhouette
smoothness across resolutions belongs to TQP-25 and remains unqualified here.
Finding `TQP-F001` permanently records the reviewer-reported moving-shadow
concern, shadows-enabled/disabled controls, native `0.5 m` versus `0.25 m`
comparison, clean seam/topology results, and the bounded resolution-limit
interpretation. `TQP-D015` later closes the finding only for the reviewed
TQP-25 Windows reference corpus; this is not proof of production visual quality.
`TQP-D014` records explicit acceptance of this bounded reference scope.
Production art direction, visual behavior outside the TQP-25 reference corpus,
dynamic weather/decals, GPU cost, and other hardware remain unqualified.

### TQP-24: Collision, Queries, And Navigation

Status: `qualified` for the native Windows Godot publication reference. Owner:
Terrain Systems Lab. Depends on: TQP-06, TQP-15,
TQP-16.

The retained native fixture requires real ArrayMesh and concave collision
resources, direct-space ray hits, authoritative field queries, terrain-derived
navigation polygons, and coherent render, collision, query, and navigation
generations before and after a committed carve. Production navigation policy,
agents, avoidance, and non-Windows servers remain unqualified.

### TQP-25: Visual Quality Corpus

Status: `qualified` for the bounded Windows reference corpus. Owner: Material
and Surface Lab. Depends on: TQP-05,
TQP-18, TQP-21, TQP-23.

The dedicated `@tool` review scene provides natural, constructed, destroyed,
and adversarial native fixtures with declared art-direction targets, fixed
still cameras, full motion sweeps, and shadow controls. Retained Windows
evidence includes exact-repeat PNGs, H.264 videos, geometry signatures, seam
and assembled-window topology reports, image-coverage checks, and temporal
change measurements. Automation passes all four fixtures but cannot accept
visual quality or close a human finding by itself. The project owner completed
the live fixture, motion, and adversarial shadow comparison; `TQP-D015` records
bounded acceptance and closes `TQP-F001` for this corpus. Production art,
large-terrain LOD and streaming, other renderer profiles, and cross-hardware
behavior remain unqualified and can reopen the finding with contradictory
evidence.

### TQP-26: Terrain Observatory

Status: `qualified` for deterministic diagnostic snapshots and signed repro
export. Owner: Terrain Systems Lab. Depends on: TQP-06, TQP-15,
TQP-16, TQP-19, TQP-20, TQP-22, TQP-24.

The observatory model retains chunk and job state, generations, LOD decisions,
edit dependencies, buffer and memory totals, timings, collision state, and
rejection reasons. Its event ring has deterministic overflow ordering, and
signed JSON repros pass export/reload validation while a tampered-repro negative
control fails. The `@tool` Terrain Observatory presents a live summary and
provides one-action repro export. Production telemetry, GPU timestamps, remote
profiling, multi-hour production soaks, and portable performance budgets remain
unqualified.

### TQP-27: Large-Terrain Performance And Soak

Status: `qualified` for the bounded native Windows 2K-world reference soak.
Owner: Terrain Systems Lab. Depends on: TQP-04, TQP-16,
TQP-19, TQP-20, TQP-22, TQP-24, TQP-26.

The retained native run uses `WorldTransvoxelTerrain` directly over a
128x16x128-chunk procedural volume, representing 2048x256x2048 cells and
299,520 catalog pages. It passes continuous traversal, four long-range
teleports, four committed edits, stale-viewer and stale-edit rejection,
resource-retirement ceilings, frame and settlement distributions, memory and
throughput budgets, durable edit-journal restart, post-restart query agreement,
and clean shutdown. The measured route spans 1,984 metres and observes more
than 280 unique render and collision chunks in the retained run.

Large-volume snapshot compaction is a required fail-closed negative control:
the native authority rejects the operation with `world snapshot manifest
validation failed` and leaves no partial output. `TQP-F002` records that open
upstream capacity limitation. `TQP-D016` therefore qualifies journal-backed
restart and the bounded reference soak, not snapshot compaction, multi-hour or
production workloads, GPU performance, other hardware, or non-Windows targets.

The separate `@tool` Large Terrain Observatory opens the exact retained
128x16x128-chunk profile in the Godot editor. It displays the complete world
envelope and catalog identity while streaming only the native viewer's bounded
render and collision residency. Its focused parity report verifies origin,
center, and far-corner windows against this standard; it is presentation
evidence and does not widen the qualified performance scope.

## Phase 4: Native Adaptive Terrain Qualification

This is the active phase. It converts the bounded contracts and reference
fixtures from TQP-01 through TQP-27 into evidence for assembled, adaptive,
edited native Transvoxel terrain. Every milestone begins `proposed`; existing
behavior may be reused only after the milestone's own independent evidence
passes.

Execution order: TQP-28 -> TQP-29 -> TQP-30 -> TQP-31 -> TQP-32 ->
TQP-33 -> TQP-34 -> TQP-35 -> TQP-36 -> TQP-37 -> TQP-38 -> TQP-39 ->
TQP-40 -> TQP-41 -> TQP-42 -> TQP-43 -> TQP-44 -> TQP-45.

### TQP-28: Field Generation And Sampling Contract

Status: `qualified` for the retained deterministic native Windows field
contract. Owner: Terrain Systems Lab and Edit Semantics Lab. Depends on:
TQP-03, TQP-05, TQP-07, TQP-08, TQP-20.

Complete when density sign, isovalue ownership, world units, deterministic
seeds, field composition order, material sampling, gradients, interpolation,
frequency limits, large-coordinate behavior, and chunk/LOD-independent sample
identity are fixed by analytical positive, boundary, and negative fixtures.

The retained `TQP-NATIVE-FIELD-WINDOWS-V1` standard fixes solid-negative and
air-positive density, isovalue zero, 0.5 metre integer-grid samples, material
ownership, normalized gradients, interpolation, explicit seeds, frequency
limits, integer-local large-coordinate conversion, and sample identity.
Adaptive LOD selection, transition assembly, production field generation, and
other platforms remain explicitly unqualified.

### TQP-29: Complex Native Field Corpus

Status: `qualified` for the bounded Windows LOD0 same-resolution native corpus.
Owner: Terrain Systems Lab and Cell Lab. Depends on: TQP-04, TQP-28.

Complete when native fixtures cover slopes, ridges, valleys, cliffs, caves,
tunnels, arches, overhangs, pillars, saddles, thin layers, high curvature,
mixed materials, exact-isovalue contacts, and large coordinates. Each fixture
requires a stable field signature, expected feature inventory, resolvability
classification, and minimized repro export.

The retained corpus contains fourteen deterministic 2x2x2 windows: slopes,
ridges and valleys, cliffs, caves, tunnels, arches, overhangs, pillars,
saddles, thin layers, high curvature, mixed materials, exact-isovalue contacts,
and million-unit coordinates. Its two native passes each cover 112 chunks and
168 shared same-LOD boundaries. Every assembled window has zero interior-open
and nonmanifold edges, and every fixture retains exact field/native geometry
signatures plus a focused repro command. This does not qualify adaptive LOD or
transition cells; those begin at TQP-30 and TQP-31.

### TQP-30: Adaptive LOD Selection And Neighbor Contract

Status: `qualified` for the bounded deterministic hierarchy reference. Owner:
Terrain Systems Lab. Depends on: TQP-05, TQP-19,
TQP-20, TQP-22, TQP-29.

Complete when the octree or equivalent hierarchy, split/merge thresholds,
hysteresis, viewer metric, parent/child coverage, maximum neighbor delta,
vertical residency, origin shifts, teleports, and invalid LOD arrangements have
deterministic policies and exhaustive structural checks.

The retained `TQP-ADAPTIVE-LOD-WINDOWS-V1` standard defines a balanced finite
octree over a 16x16x16 LOD0-chunk root through LOD4. Ten cold/warm scenarios
cover interior, face, edge, vertical exterior, far-viewer, and signed
million-chunk origins. Exact coverage, parent/child ownership, maximum
face-neighbor delta one, full vertical ownership, hysteresis, origin shifts,
and one-selection teleport convergence pass. Six injected invalid arrangements
prove that overlap, holes, misalignment, invalid LOD, neighbor delta, and
incomplete split records are detected. Dynamic publication and production
streaming remain unqualified.

### TQP-31: Regular And Transition Assembly Matrix

Status: `qualified` for the retained native Windows static assembly matrix.
Owner: Terrain Systems Lab and Cell Lab. Depends on: TQP-29, TQP-30.

Complete when assembled native chunks exercise every transition-face
orientation, regular/transition ownership rule, permitted LOD relationship,
edge and corner meeting, positive and negative coordinates, winding, normals,
materials, and empty/full boundary case without fallback geometry.

The retained `TQP-TRANSITION-ASSEMBLY-WINDOWS-V1` matrix makes 658 direct
`WorldTransvoxelCellProbe` chunk calls with no fallback. It proves exact
coarse-to-four-fine interface equality on every face for LOD 1/0, 2/1, and
3/2, plus all twelve perpendicular edge masks, eight corner masks, all faces,
and four fine regular neighbors for every requested face. It also covers signed
coordinates, four materials, and empty/full controls. Winding is checked
for shared-edge consistency and connected-component normal polarity, matching
the native finalizer contract. One local skinny-triangle normal disagreement is
retained as a diagnostic and is not a component winding defect. Dynamic or
arbitrary adaptive arrangements remain unqualified; TQP-32 separately owns
the bounded world-boundary policy.

### TQP-32: Chunk, World Boundary, And Enclosure Policy

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-02, TQP-03,
TQP-05, TQP-29, TQP-30, TQP-31.

Complete when internal chunk interfaces, finite-world edges, vertical limits,
outside-field sampling, closed versus intentionally open contours, caps,
unloaded neighbors, and catalog limits have explicit ownership. Artificial
skirts or hidden overlap cannot count as a topology correction.

The retained Windows reference runs four 2x2x2 native windows at LOD0 and LOD2
twice, for 64 direct chunk calls, plus five LOD2 unloaded-neighbor calls. Closed
volume and capped-terrain fixtures have zero open or nonmanifold edges; the declared
open fixture has 142 exterior open edges confined to the declared +/-X and
+/-Z planes, with none on +/-Y. Every fixture serves 6,936
native gradient-halo samples outside its finite domain across all six faces.
Twelve injected controls prove that invalid catalogs, resident-dependent density,
skirts, and overlap are rejected. The exact eight-chunk catalog, partial
residency, signatures, minimized repros, and `@tool` Boundary Observatory are
retained. General topology beyond the retained TQP-33 oracle fixtures, dynamic
terrain, larger catalogs, production performance, and other platforms remain
unqualified.

### TQP-33: Independent Geometry And Topology Oracles

Status: `qualified`. Owner: Cell Lab and Terrain Systems Lab. Depends on:
TQP-04, TQP-29, TQP-31, TQP-32.

Complete when assembled surfaces pass independent edge multiplicity,
non-manifold, duplicate/overlap, orientation, bounds, finite-value, component,
Euler-characteristic where applicable, ray parity, signed-volume, and field
resampling checks. Every oracle requires an injected-defect negative control.

The retained Windows reference normalizes five native assemblies without using
the existing native evidence validator: closed LOD0 and LOD2 volumes, capped
terrain, intentional open terrain, and one coarse/fine transition assembly.
Seventy-four cold/warm native calls pass thirteen independent checks. Thirteen
injected defects prove every detector, including index and degenerate-triangle
integrity in addition to the roadmap checks. The report retains exact geometry
signatures, minimized fixture arguments, p50/p95/p99/worst timing distributions,
retained and peak memory, provenance, and a separate `@tool` observatory. The
maximum measured fixed-point field-resampling residual is 0.03125 density units
under a retained 0.0313 ceiling. Partial coplanar overlap, arbitrary terrain,
randomized fields, dynamic systems, production performance, and other platforms
remain unqualified.

### TQP-34: Adversarial, Randomized, And Minimized Repro Corpus

Status: `qualified`. Owner: Terrain Systems Lab and Cell Lab. Depends on:
TQP-04, TQP-29, TQP-31, TQP-33.

Complete when seeded fuzzing varies field parameters, isovalue coincidences,
LOD arrangements, coordinates, materials, and traversal order; failures shrink
to stable fixtures; cold/warm and worker-order replays agree; and the retained
corpus includes every previously corrected terrain defect.

The retained Windows corpus fixes four effective generated-field seeds across
closed-wave, closed-blob, exact-isovalue, and mixed-LOD profiles, plus three
fixed canonical tangent-edit, million-grid, and LOD3 positive-X corrected
regressions. Twenty-eight cold, warm, reverse-
completion, and seeded-completion replays make 240 direct native chunk calls;
all normalized geometry signatures agree and every replay passes the TQP-33
independent oracle. The corpus covers LOD levels zero through three, two
transition faces, signed and million-grid coordinates, nine material IDs, and
4,832 exact-isovalue sample hits. A deterministic triangle delta debugger
shrinks an injected 25-triangle duplicate control to a stable two-triangle,
three-vertex fixture. `TQP-D011`, `TQP-D018`, and `TQP-D019` are retained as
direct corrected-behavior or corrected-judgment regressions. Serialized
completion-order permutations are qualified here; actual concurrent execution
and dynamic publication remain reserved for TQP-35 and TQP-42. `cold` means
the first canonical replay on a fresh per-case probe and `warm` its immediate
repeat; these are correctness lanes, not hardware-cache isolation claims.

### TQP-35: Dynamic LOD Publication And Temporal Stability

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-15, TQP-17,
TQP-19, TQP-22, TQP-30, TQP-31, TQP-33, TQP-34.

Complete when split, merge, replacement, cancellation, stale-result rejection,
origin shift, teleport, and unload/reload publish coherent generations without
holes, overlaps, double collision, stale materials, flicker, or unbounded
popping. Automated frame-state checks and retained motion evidence are both
required.

`TQP-D023` qualifies the bounded Windows debug profile over actual native
LOD1/LOD0 publication. The retained run audits 1,184 frames and records eight
splits, four merges, 603 replacement frames, 50 transition completions, rapid
viewer coalescing, stale-result rejection, presentation-parent rebasing,
teleport, clean unload, and exact reload agreement. All hole, render-overlap,
double-collision, generation-incoherence, same-generation material-mutation,
and frame-failure counters are zero. The first candidate was rejected after
recording 289 double-collision frames; world-transvoxel was corrected to stage
replacement collision bodies until atomic hierarchy publication. Dynamic
LOD2 and deeper hierarchies, native floating-origin remapping, crossfade
quality, adaptive edits, arbitrary fault timing, production performance, and
other platforms remain explicitly unqualified.

### TQP-36: Edit Invalidation And Incremental Remeshing

Status: `qualified`. Owner: Edit Semantics Lab and Terrain Systems Lab. Depends
on: TQP-06, TQP-12, TQP-15, TQP-17, TQP-29, TQP-30, TQP-31, TQP-35.

Complete when edit bounds, sample halos, regular and transition dependents,
parent/child invalidation, job cancellation, batching, no-op edits, and dirty
resource retirement rebuild exactly the required set and never leave stale or
unnecessarily rebuilt terrain.

`TQP-D024` qualifies the bounded Windows debug LOD1/LOD0 profile using an
independent padded-sample-footprint oracle over all 83 active native
application records, including empty render payloads. Seven retained scenarios
cover coarse-parent and fine-child interiors, a same-LOD boundary halo, a
mixed regular/transition dependency, disjoint sphere-plus-box batching, an
unloaded no-op, and rapid supersession. Every observed generation change
equals the independently expected set; all unrelated generations remain
stable. The run records 14 replacements, 14 page-meshing cancellations, one
empty transaction, four stale superseded-resource rejections, and zero visible
holes, render overlaps, double collisions, or frame failures. Digging,
construction, brush semantics and quality, materials, persistence, deeper LOD,
production performance, and other platforms remain explicitly unqualified.

### TQP-37: Digging And Construction Across Adaptive LOD

Status: `proposed`. Owner: Edit Semantics Lab and Terrain Systems Lab. Depends
on: TQP-10, TQP-11, TQP-13, TQP-14, TQP-29, TQP-31, TQP-36.

Complete when resolvable and intentionally under-resolved digging and
construction cross chunks, transition faces, edges, corners, vertical layers,
origin shifts, and unloaded regions. Repeated edits, undo/redo, unload/reload,
and later refinement must preserve the authoritative field and expose no crack,
duplicate surface, edit loss, or LOD-dependent semantic change.

### TQP-38: Adaptive Material And Texture Continuity

Status: `proposed`. Owner: Material and Surface Lab. Depends on: TQP-18,
TQP-21, TQP-23, TQP-25, TQP-31, TQP-35, TQP-37.

Complete when material identity, blend reduction, triplanar anchoring, normals,
tangents, mip choice, decals, edited surfaces, and categorical boundaries stay
coherent across regular/transition geometry, dynamic LOD replacement, origin
shifts, and large coordinates with retained diagnostic and lit evidence.

### TQP-39: Adaptive Render, Collision, Query, And Navigation Agreement

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-24, TQP-31,
TQP-35, TQP-37.

Complete when render mesh, collision, authoritative field queries, ray hits,
and terrain-derived navigation agree on generation, bounds, occupancy, and
retirement through LOD changes and edits. The corpus must include transition
regions, caves, overhangs, thin features, teleports, and stale-publication
negative controls.

### TQP-40: Multi-Layer Adaptive Streaming And Residency

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-19, TQP-20,
TQP-22, TQP-27, TQP-30, TQP-35.

Complete when native streaming handles large horizontal and vertical terrain,
caves above and below the viewer, adaptive parent/child coverage, prefetch,
eviction, teleports, origin shifts, memory ceilings, resource retirement, and
visibility without the former single-layer reference assumptions.

### TQP-41: Adaptive Persistence And Stream Replay

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-13, TQP-16,
TQP-20, TQP-26, TQP-35, TQP-37, TQP-40.

Complete when complex edited fields, adaptive residency state, journal replay,
supported snapshot compaction, migration, crash recovery, distant unloaded
edits, and post-restart regeneration reproduce authoritative queries and
derived resources. `TQP-F002` must be resolved or remain an explicit capacity
limit in the qualified envelope.

### TQP-42: Fault Injection And Cross-Order Determinism

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-15, TQP-17,
TQP-26, TQP-34, TQP-35, TQP-36, TQP-37, TQP-39, TQP-40, TQP-41.

Complete when randomized worker completion, cancellation, duplicate and stale
requests, save interruption, malformed input, allocation failure, rapid viewer
motion, and shutdown produce deterministic authoritative state or a declared
fail-closed error. Resource and event traces must identify the first divergent
generation.

### TQP-43: Complex Terrain Visual And Temporal Corpus

Status: `proposed`. Owner: Material and Surface Lab and Terrain Systems Lab.
Depends on: TQP-23, TQP-25, TQP-26, TQP-31, TQP-35, TQP-37, TQP-38, TQP-39,
TQP-40, TQP-42.

Complete when fixed stills and motion paths recursively inspect representative
and adversarial terrain at overview, chunk, transition, and cell scales from
multiple angles. Human review must cover silhouettes, cracks, overlaps,
popping, flicker, shadows, texture scale, edited surfaces, caves, overhangs,
and visual pleasantness against declared targets; automation cannot accept the
milestone by itself.

### TQP-44: Complex Adaptive Terrain Performance And Soak

Status: `proposed`. Owner: Terrain Systems Lab. Depends on: TQP-04, TQP-26,
TQP-27, TQP-34, TQP-35, TQP-37, TQP-38, TQP-39, TQP-40, TQP-41, TQP-42,
TQP-43.

Complete when complex multi-layer adaptive terrain passes repeated cold/warm
generation, traversal, teleports, LOD churn, digging, construction, material
edits, persistence, recovery, and shutdown with p50/p95/p99/worst timings,
throughput, resident and peak memory, queue depth, resource ceilings, workload
signatures, provenance, and retained long-soak drift evidence.

### TQP-45: Native Adaptive Terrain Authority Gate

Status: `proposed`. Owner: Terrain Qualification Program. Depends on: TQP-28
through TQP-44.

Complete when every Phase 4 milestone is qualified for one coherent declared
envelope, all open findings have explicit disposition, independent and visual
reviews pass, reports reproduce from pinned revisions, and the authority matrix
states exactly what world-transvoxel, Cell Lab, and Terrain Lab do and do not
prove. Only this milestone may promote Gate E.

## Phase 5: Destruction And Structural World Systems

This phase qualifies destructive edits and optional world systems only after
Gate E establishes trustworthy adaptive terrain behavior.

Execution batches: (TQP-46, TQP-47, TQP-48, TQP-49, TQP-50) -> TQP-51.

Reference behavior exists, but these milestones remain unqualified until their
native, temporal, persistence, visual, and performance gaps close.

### TQP-46: Explosion Corpus

Status: `implemented`. Owner: Edit Semantics Lab and Structural Systems Lab.
Depends on: Gate E, TQP-09, TQP-10, TQP-11, TQP-12, TQP-13, TQP-14, TQP-17.

Complete when radial and directed blasts, material damage, bounded noise,
overlap, fragmentation inputs, collision timing, replay, and cost are
qualified.

### TQP-47: Connectivity And Support

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gate E, TQP-02, TQP-11, TQP-12.

Complete when anchors, solid connectivity, support graphs, floating terrain,
material strength, and under-resolved supports have deterministic policies.

### TQP-48: Fluids And Hydrology

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gate E, TQP-05, TQP-16, TQP-19.

Complete when terrain-water intersections, coastlines, caves, drainage,
flooding, edits, LODs, persistence, and rendering have defined ownership.

### TQP-49: Vegetation And Object Placement

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gate E, TQP-08, TQP-16, TQP-19.

Complete when placement provenance, invalidation, regeneration, persistence,
collision, and destruction after terrain edits are deterministic.

### TQP-50: Roads, Structures, And Authored Terrain

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gate E, TQP-08, TQP-11, TQP-16.

Complete when stamps, foundations, tunnels, bridges, authored construction,
procedural fields, edits, materials, and LODs compose predictably.

### TQP-51: Collapse And Debris

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gate E, TQP-24, TQP-46, TQP-47.

Complete when separated components, collapse decisions, rigid-body conversion,
remeshing, collision, cleanup, persistence, and replay are qualified.

## Phase 6: GPU Candidate Qualification

This phase evaluates GPU acceleration against the qualified CPU reference. It
does not replace CPU authority or begin by rewriting the lab.

Execution batches: TQP-52 -> TQP-53 -> TQP-54 -> (TQP-55, TQP-56) -> TQP-57.

TQP-52 is specified. Later batches remain blocked until concrete GPU field,
meshing, residency, and multi-vendor hardware targets exist.

### TQP-52: GPU Architecture Decision

Status: `specified`. Owner: Backend Qualification Lab. Depends on: Gates A
and E.

Complete when field evaluation, meshing, buffer residency, rendering,
collision readback, synchronization, target APIs, and expected benefit are
separate measured decisions.

### TQP-53: GPU Field Evaluation

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-07,
TQP-08, TQP-12, TQP-28, TQP-29, TQP-52.

Complete when GPU density, gradients, materials, edits, filtering, precision,
and determinism pass analytical and CPU differential evidence.

### TQP-54: GPU Meshing Candidate

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-31,
TQP-33, TQP-34, TQP-52, TQP-53.

Complete when GPU regular, transition, and chunk extraction exists as a
candidate without weakening or replacing the native CPU reference.

### TQP-55: CPU/GPU Differential Corpus

Status: `blocked`. Owner: Backend Qualification Lab and Cell Lab. Depends on:
TQP-34, TQP-45, TQP-54.

Complete when topology, seams, feature survival, materials, edits, bounds, and
numeric tolerances pass the shared primitive and terrain corpora.

### TQP-56: GPU Residency And Publication

Status: `blocked`. Owner: Backend Qualification Lab and Terrain Systems Lab.
Depends on: TQP-15, TQP-22, TQP-35, TQP-40, TQP-42, TQP-54.

Complete when allocation, reuse, indirect drawing, transfer, collision
readback, stale work, synchronization, and device-loss recovery are qualified.

### TQP-57: Cross-Hardware GPU Matrix

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-04,
TQP-44, TQP-55, TQP-56.

Complete when correctness, reproducibility, performance, memory, drivers,
vendors, graphics APIs, and explicitly unsupported hardware are recorded.

## Phase 7: Production Terrain And Release Qualification

This phase begins only with a pinned production terrain candidate and
qualified prerequisite gates. It proves the addon boundary, authoring,
networking when applicable, integration-game parity, release matrix, and
long-haul behavior before publishing Standard 1.0.

Execution batches: TQP-58 -> (TQP-59, TQP-60) -> TQP-61 -> TQP-62 ->
TQP-63 -> TQP-64.

This phase is blocked because a pinned candidate production addon and its later
release evidence do not yet exist.

### TQP-58: Production Addon Boundary

Status: `blocked`. Owner: `world-transvoxel-terrain`. Depends on: Gates A
through E.

Complete when runtime APIs, data ownership, dependencies, configuration,
extension points, threading, errors, and unsupported behavior are frozen for a
candidate release.

### TQP-59: Authoring And Inspection Workflow

Status: `blocked`. Owner: `world-transvoxel-terrain`. Depends on: TQP-08,
TQP-10, TQP-11, TQP-12, TQP-13, TQP-14, TQP-17, TQP-18, TQP-21, TQP-23,
TQP-25, TQP-26, TQP-37, TQP-38, TQP-43, TQP-45, TQP-46, TQP-58.

Complete when brushes, previews, undo/redo, material authoring, diagnostics,
imports, profiling, and one-action repro export support real workflows.

### TQP-60: Networking And Recovery

Status: `blocked`. Owner: Production terrain and integration layers. Depends
on: TQP-13, TQP-16, TQP-17, TQP-41, TQP-42, TQP-58.

Complete when replication, ordering, conflict resolution, late join, save
recovery, disconnects, corruption, and authority transitions are qualified for
the declared multiplayer model.

### TQP-61: Integration-Game Parity

Status: `blocked`. Owner: Integration game and `world-transvoxel-terrain`.
Depends on: TQP-27, TQP-43, TQP-44, TQP-45, TQP-58, TQP-59.

Complete when representative gameplay terrain, edits, saves, rendering,
collision, and failures reduce to canonical qualification evidence.

### TQP-62: Production Release Matrix

Status: `blocked`. Owner: Terrain Qualification Program. Depends on:
applicable TQP-01 through TQP-61 milestones.

Complete when supported platforms, renderers, native artifacts, hardware,
upgrade paths, visuals, performance budgets, and explicitly unqualified scope
form a reproducible release bundle.

### TQP-63: Long-Haul Certification

Status: `blocked`. Owner: Terrain Qualification Program. Depends on: TQP-62.

Complete when extended traversal, editing, construction, destruction,
save/load, streaming, origin shifting, device events, and fault injection pass
without correctness, memory, or performance drift.

### TQP-64: Production Terrain Standard 1.0

Status: `blocked`. Owner: Terrain Qualification Program. Depends on: TQP-63.

Complete when the final evidence bundle is reviewed, versioned, reproducible,
and explicit about every qualified and unqualified claim. This milestone marks
a standard, not an assertion that future terrain work is finished.

## Current Program State

The program records every milestone at a truthful evidence state:

- `TQP-01` through `TQP-36` are qualified
  for their narrow contract, native Windows reference, or reference-model
  scopes. Gate B is qualified; its native chunk rebuild benchmark remains a
  background/debug reference and is not a production frame-time claim.
- `TQP-28` through `TQP-36` qualify the deterministic field contract, bounded
  LOD0 complex native corpus, finite adaptive selector, and static native
  transition-assembly matrix, bounded boundary/enclosure policy, and independent
  geometry/topology oracles, seeded adversarial/minimized repro corpus, and
  bounded native dynamic LOD publication with temporal ownership checks, and
  exact native edit invalidation with incremental remeshing.
  `TQP-37` through `TQP-45` remain proposed, so
  the program makes no Gate E adaptive-terrain authority claim.
- `TQP-46` through `TQP-51` retain the previously implemented destruction and
  structural reference behavior under their revision-19 identifiers.
- `TQP-52` is specified and requires measured GPU-candidate benefit.
- `TQP-53` through `TQP-64` are blocked by named external targets and exit
  conditions in `program_blockers.json`.

The next dependency-ordered milestone is TQP-37, digging and construction
across adaptive LOD. TQP-27 remains qualified through `TQP-D016` only for its
bounded native Windows 2K-world soak and durable edit-journal restart.
`TQP-F002` retains large-volume snapshot compaction as an open upstream
capacity issue. Gate D is qualified only for that bounded reference claim;
Gate E is open, and destruction, GPU, and production promotion are frozen
behind it. A milestone may advance only when its declared evidence passes.

## What Comes Next

TQP-32 now defines the bounded chunk and finite-world boundary policy:
authoritative outside-field halo samples, density-owned caps, declared open
contours, residency-independent chunk geometry, exact catalog limits, and no
skirts or hidden overlap.

TQP-33 provides independent geometry/topology oracles and one injected defect
per check without calling the implementation validator. TQP-34 now applies
those oracles to retained seeded fields, exact-isovalue coincidences, mixed LOD,
large coordinates, corrected regressions, traversal permutations, and a
deterministic minimized-failure control. It does not claim arbitrary fuzzing or
actual concurrent publication.

TQP-35 begins the changing-terrain system and qualifies the bounded native
LOD1/LOD0 publication timeline. TQP-36 now qualifies exact bounded edit
invalidation and incremental remeshing mechanics. TQP-37 through TQP-42 qualify
digging and construction across LOD boundaries,
material continuity, render/collision/query/navigation agreement, streaming,
persistence, replay, failure recovery, and determinism under different work
orders. These milestones determine whether the correct static primitive stays
correct while a viewer moves and terrain changes over time.

TQP-43 and TQP-44 provide the final adaptive-terrain review layer. TQP-43
requires broad visual and temporal inspection of complex terrain, while TQP-44
measures sustained performance, memory, residency, queues, and long-running
stability under the complete qualified workload. Spatial or temporal
milestones should expose focused `@tool` observatories and reproducible
captures for human inspection, but screenshots remain supporting evidence and
cannot replace machine invariants or retained reports.

TQP-45 is Gate E. It can qualify only a coherent envelope in which all earlier
Phase 4 contracts agree. Passing it would mean that the lab has an
authoritative bounded reference for native adaptive edited Transvoxel terrain;
it would not by itself mean that a production game terrain is finished.

Only after Gate E should the program reassess the existing destruction and
structural work in TQP-46 through TQP-51. GPU work in TQP-52 through TQP-57 is
a candidate backend measured against the qualified CPU reference, not a
replacement chosen in advance. TQP-58 through TQP-64 then address production
integration, networking, tooling, compatibility, release evidence, and the
final Production Terrain Standard. Those later phases remain separate so they
cannot weaken or obscure the terrain-core evidence now being built.

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
- `TQP-D006`: replace domain-grouped identifiers with the former revision-5
  TQP-01 through TQP-46 sequence without changing milestone evidence state;
  `TQP-D017` supersedes only its unqualified TQP-28 onward numbering.
- `TQP-D007`: qualify TQP-19 and TQP-20 for deterministic reference scopes and
  retain TQP-18 as implemented pending explicit human visual review.
- `TQP-D008`: accept the retained TQP-18 material-blending diagnostic and
  promote only its deterministic reference material-model scope.
- `TQP-D009`: qualify the narrow TQP-22 horizontal CPU visibility/residency
  reference and retain TQP-21 pending review of the corrected observatory.
- `TQP-D010`: calibrate TQP-19 and TQP-22 debug reference-policy regression
  ceilings in focused retained runners and label post-soak full-program timing
  distributions as observation-only, without making a production performance
  claim.
- `TQP-D011`: retain the canonical smoothed-crater tangent crack as a real
  native defect, correct early near-degenerate removal upstream without moving
  the fixture or adding a fallback, and require exact all-neighbor seam evidence
  in the observatory and qualification program. Rebaseline the affected TQP-11,
  TQP-12, and TQP-14 geometry signatures only after their semantic, seam, and
  collision invariants pass under the corrected native revision.
- `TQP-D012`: record that all-neighbor seam equality still missed 24 interior
  open edges at exact-isovalue tangent poles, require assembled finite-window
  edge multiplicity plus an injected-hole negative control, and move endpoint
  regularization before native cell-level degenerate cleanup.
- `TQP-D013`: accept the corrected deterministic Terrain Observatory render for
  the bounded TQP-21 reference texture-system scope.
- `TQP-D014`: accept the bounded TQP-23 reference surface-shading contract while
  retaining TQP-F001 and production visual quality for TQP-25.
- `TQP-D015`: accept the bounded four-fixture TQP-25 Windows reference corpus
  and close TQP-F001 for that scope while retaining production, large-terrain,
  and cross-hardware visual quality as unqualified.
- `TQP-D016`: accept the bounded native Windows TQP-27 2K-world soak and
  journal-backed restart evidence while retaining large-volume snapshot
  compaction in `TQP-F002` and production, multi-hour, GPU, cross-hardware, and
  non-Windows performance as unqualified.
- `TQP-D017`: preserve accepted TQP-01 through TQP-27 evidence, insert the
  missing TQP-28 through TQP-45 native adaptive-terrain qualification phase,
  shift only unqualified later work, and freeze destruction, GPU, and
  production promotion until Gate E passes.
- `TQP-D018`: qualify TQP-28 and TQP-29 for the retained deterministic field
  contract and bounded Windows LOD0 complex native-field corpus, correct the
  large-coordinate lab oracle to a window-relative frame, and retain adaptive
  LOD, transitions, production terrain, and other platforms as unqualified.
- `TQP-D019`: qualify TQP-30 and TQP-31 for the bounded deterministic adaptive
  selector and retained native Windows transition-assembly matrix, align the
  winding oracle with the native connected-component contract, and retain
  dynamic terrain, enclosure, independent-oracle, and production claims as
  unqualified.
- `TQP-D020`: qualify TQP-32 for the bounded native Windows boundary,
  outside-field halo, enclosure, unloaded-neighbor, and exact catalog policy;
  reject skirts, overlap, and resident-dependent density while retaining
  general topology, dynamic terrain, larger catalogs, and production claims as
  unqualified.
- `TQP-D021`: qualify TQP-33 for the bounded independent triangle-soup oracle
  suite over five native assemblies, with one detected injected defect per
  check, exact signatures, field-residual bounds, performance telemetry, and
  arbitrary/randomized/dynamic terrain claims retained as unqualified.
- `TQP-D022`: qualify TQP-34 for the bounded four-seed plus three fixed-
  regression Windows adversarial corpus, exact cold/warm and completion-order
  replay, deterministic
  two-triangle failure minimization, and retained TQP-D011/TQP-D018/TQP-D019
  corrected regressions while leaving actual concurrency and dynamic terrain
  publication to later milestones.
- `TQP-D023`: qualify TQP-35 for bounded native LOD1/LOD0 dynamic publication
  after rejecting the original double-collision result and correcting upstream
  replacement collision staging; retain deeper LOD, edits, crossfade, fault
  injection, production performance, and other platforms as unqualified.
- `TQP-D024`: qualify TQP-36 for bounded native exact edit invalidation over
  all active application records, including empty payloads, with independent
  padded-footprint set equality, batching, no-op, cancellation, stale-result,
  resource-retirement, performance, trace, and editor evidence; retain adaptive
  digging/construction semantics and all later terrain claims as unqualified.
