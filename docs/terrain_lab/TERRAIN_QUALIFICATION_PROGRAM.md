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

## Program Goal And Priority

The program's release goal is a separate, standalone production terrain addon
that provides correct, seamless, large, smooth volumetric terrain with adaptive
resolution, bounded streaming, responsive digging and construction, targeted
collision, predictable memory, stable frame pacing, and adjustable quality and
power profiles.

Work advances in this order:

1. prove field, meshing, topology, edit, material, collision, persistence, and
   adaptive-terrain correctness with the native CPU authority;
2. prove fast arrival, edit response, targeted collision, rendering, queues,
   memory, power, and long-running recovery at representative large-world scale;
3. release the simplest qualified CPU production addon as the baseline;
4. qualify and release GPU acceleration differentially against that baseline;
5. only then qualify game-oriented systems such as explosions, collapse,
   fluids, vegetation, roads, and networking.

Correctness and authority cannot be traded for a benchmark result. Performance
work must prefer measured, standard, widely accepted techniques and simple
ownership rules. Experimental optimizations remain isolated candidates until
they preserve every applicable invariant. Longer initial preparation is
acceptable when it measurably improves sustained behavior, but movement to a
distant region must not cause unexplained multi-second waits before local
rendering, digging, construction, queries, or required collision become ready.

## Authority Chain

```text
field, edit, coordinate, and resolution contracts
    -> world-transvoxel native meshing authority
        -> Cell Lab meshing qualification
            -> edit and surface qualification
                -> bounded terrain-system qualification
                    -> native adaptive-terrain qualification
                        -> standalone CPU production release
                            -> GPU backend qualification and release
                                -> optional post-release game systems
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

The specified low-power profile is
`low_power_performance_profile.json`. It targets sustained 60 FPS inside a
declared 16 GPU-board WPF60 boundary after thermal warmup, preserving the
old `gpu-marching-cubes` `nvidia-smi power.draw` benchmark meaning. CPU-package,
battery, DC-input, and AC-input power are separate observation boundaries and
must not be treated as interchangeable with GPU-board WPF60. The target
requires frame-pacing, responsiveness, CPU/GPU time, memory, power, and
energy-per-work evidence. Render, collision, navigation, and authoritative
query residency are independent: collision is requested only by bounded physics
invokers and must not be generated for every visible chunk by default. The target profile remains unqualified as an achieved-performance claim
until the retained target misses are resolved. The exact TQP-48 long run is
qualified only as baseline evidence and measurement protocol evidence.

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
  `TQP-50`. Gate D's bounded reference models do not satisfy this gate.
- Gate F: the standalone CPU production terrain release requires `TQP-51`
  through `TQP-57` after Gate E.
- Gate G: the GPU production backend release requires `TQP-58` through
  `TQP-64` after the CPU release; CPU authority remains the differential
  reference unless a later reviewed decision changes it.
- Gate H: optional post-release game systems occupy `TQP-65` through `TQP-71`.
  Gate H is not a prerequisite for releasing the terrain addon.

## How To Follow This Program

The milestones below are numbered and arranged in ground-up execution order.
Items inside parentheses may proceed in parallel. Arrows between batches are
promotion order: investigation may happen early, but qualification cannot skip
an earlier dependency.

The machine-readable `execution_plan.json` mirrors the same order but is not a
second human roadmap. Program revision 40 preserves every qualified TQP-01
through TQP-47 claim, keeps the ordered CPU/GPU release sequence from
`TQP-D033`, corrects TQP-48's inherited low-power target through
`TQP-D036`, and closes Gate E for the bounded CPU authority envelope through
`TQP-D037`, and qualifies the first three candidate runtime and integration
milestones through `TQP-D039` without advancing release certification.
Earlier identifier migrations remain retained in `TQP-D006`, `TQP-D017`, and
`TQP-D030` as history.

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
Gate E now passes for the declared bounded Windows CPU adaptive-terrain
envelope. That claim is still narrower than production: it does not qualify a
standalone runtime API, integration-game migration, non-Windows behavior, GPU
backend, or the full low-power target pass.

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
equivalence remains explicitly unqualified until TQP-54 through TQP-58.

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
TQP-40 -> TQP-41 -> TQP-42 -> TQP-43 -> TQP-44 -> TQP-45 -> TQP-46 ->
TQP-47 -> TQP-48 -> TQP-49 -> TQP-50.

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
and dynamic publication remain reserved for TQP-35 and TQP-43. `cold` means
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

Status: `qualified`. Owner: Edit Semantics Lab and Terrain Systems Lab. Depends
on: TQP-10, TQP-11, TQP-13, TQP-14, TQP-29, TQP-31, TQP-36.

Complete when resolvable and intentionally under-resolved digging and
construction cross chunks, transition faces, edges, corners, vertical layers,
origin shifts, and unloaded regions. Repeated edits, undo/redo, unload/reload,
and later refinement must preserve the authoritative field and expose no crack,
duplicate surface, edit loss, or LOD-dependent semantic change.

`TQP-D025` qualifies the bounded Windows debug LOD1/LOD0 profile through six
isolated native-runtime scenarios: transition-face carving, edge/corner
material construction, repeated smooth tunnel strokes, an initially
under-resolved construction that becomes visible after refinement and is then
held by native edit-LOD retention, an unloaded edit loaded later, and
reconstructive undo/redo. Exact live interface-edge multisets agree on every
selected transition, face, edge, and corner plane; all retained meshes contain
zero exact duplicate, degenerate, or nonfinite triangles. Authoritative sample
identity survives origin movement, unload/reload, and durable restart, and
more than 4,000 audited frames contain zero visible-hole, render-overlap,
double-collision, or frame failures. Generic in-place CSG undo is not exposed
by the native API, so only deterministic fresh-world reconstruction from the
enabled ordered command ledger is qualified. The measured timings are Windows
debug diagnostics, and this small fixture's bounded 48/64 collision profile is
not a production collision-residency or 60 FPS/16 W claim.

### TQP-38: Adaptive Material And Texture Continuity

Status: `qualified`. Owner: Material and Surface Lab. Depends on: TQP-18,
TQP-21, TQP-23, TQP-25, TQP-31, TQP-35, TQP-37.

The retained Windows debug fixture qualifies native material IDs, authored
provenance, eight-channel generated/authored weights, normal/tangent validity,
and authoritative paint/construction queries across regular and transition
surfaces. A deterministic LOD cycle shares 6,051 of 6,105 original unique
positions and changes zero shared-position payloads while explicitly retaining
the native topology replacements and extra edit-retention chunks. The reference
shader qualifies eight texture layers, seven mip levels, world-space triplanar
diagnostics, and exact presentation-origin compensation with inspected lit,
material, and provenance captures. Production art quality, arbitrary blends,
decals, texture streaming, release performance, deeper LOD, and other platforms
remain unqualified.

### TQP-39: Adaptive Render, Collision, Query, And Navigation Agreement

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-24, TQP-31,
TQP-35, TQP-37.

The retained Windows debug fixture qualifies same-generation native render and
regular-cell collision publication, authoritative scalar crossings against
Godot physics rays, bounded independent collision demand, teleport retirement,
stale-revision rejection, staged old-pair stability, and joint post-edit
replacement for a cave, surface-connected overhang, thin construction, and
staged crater. It exposed and required correction of the upstream default
512-largest-triangle collision cap, which had removed valid cave walls and
crater floors while render/query authority remained present. Consumer-derived
Godot navigation uses only upward native collision triangles at a declared
0.05-meter cell size and is keyed to the native active-state signature; it is
not world-transvoxel authority. Production collision residency, navigation
tiling/agents, performance, deeper LOD, other platforms, and GPU authority
remain unqualified.

### TQP-40: Multi-Layer Adaptive Streaming And Residency

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-19, TQP-20,
TQP-22, TQP-27, TQP-30, TQP-35.

Complete when native streaming handles large horizontal and vertical terrain,
caves above and below the viewer, adaptive parent/child coverage, prefetch,
eviction, teleports, origin shifts, memory ceilings, resource retirement, and
visibility without the former single-layer reference assumptions.

Qualification decision `TQP-D028` retains a bounded Windows debug native
1536x512x1536-cell `rolling_hills_cave` catalog. The pinned cave,
multi-viewer, and teleport windows contain LOD0 through LOD2, prove
authoritative vertical crossings above and below the underground viewer,
unique coarse prefetch contribution, old-window eviction, bounded resources,
and complete viewer drain. The `@tool` observatory renders only native
resources. Native floating origin, production performance or power, collision
policy, non-Windows platforms, and production terrain remain unqualified.

### TQP-41: Adaptive Persistence And Stream Replay

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-13, TQP-16,
TQP-20, TQP-26, TQP-35, TQP-37, TQP-40.

Complete when complex edited fields, adaptive residency state, journal replay,
supported snapshot compaction, migration, crash recovery, distant unloaded
edits, and post-restart regeneration reproduce authoritative queries and
derived resources. `TQP-F002` must be resolved or remain an explicit capacity
limit in the qualified envelope.

Qualification decision `TQP-D029` retains a 44-page native-baked LOD1/LOD0
fixture with durable central cave/construction and initially unloaded distant
construction transactions. It qualifies fresh-runtime committed-prefix and
full-journal query replay, inherited TQP-26 truncated-tail recovery, supported
compaction, fail-closed staging, migration, and compacted distant resource
regeneration. Same-node reuse across distinct stopped worlds, direct distant
coarse-page meshing before compaction, large-volume compaction beyond
`TQP-F002`, operating-system fault injection, networking, and production save
authority remain unqualified.

### TQP-42: Sparse Hierarchy Storage And Large-World Compaction

Status: `qualified`. Owner: Terrain Systems Lab and Edit Semantics Lab. Depends
on: TQP-13, TQP-16, TQP-20, TQP-27, TQP-30, TQP-40, TQP-41.

Complete when the native authority has a deterministic, measured sparse
hierarchy storage contract for large adaptive worlds. An octree is a valid
candidate, but the contract permits an equivalent sparse spatial index,
implicit procedural hierarchy with sparse baked/edit overlays, or another
representation that passes the same evidence. Selection must be based on
results rather than the data-structure name.

Qualification requires exact page-presence, ancestor/child, neighbor, range,
and viewer-root queries across dense, sparse, vertically layered, edited, and
large-coordinate fixtures. The runtime hot path must not require materializing
every possible page key, and catalog, index, cache, edit-overlay, and resident
memory must have separate counters and declared ceilings. Cold/warm startup,
lookup, traversal, insertion, edit invalidation, serialization, migration, and
compaction require p50/p95/p99/worst timings, bytes per declared and resident
page, peak memory, deterministic signatures, and comparison with the retained
flat sorted-catalog baseline.

The existing 299,520-page 2048x256x2048-cell reference must compact, reopen,
replay committed edits, and reproduce authoritative samples and adaptive
resources under bounded peak memory and atomic publication. Corruption,
duplicate keys, missing ancestors or descendants, interrupted output, and
capacity exhaustion must fail closed. `TQP-F002` closes only when that retained
large-world evidence passes. The `@tool` observatory must expose hierarchy
shape, declared versus resident pages, index/cache bytes, lookup and compaction
work, and localized edit overlays without manufacturing fallback terrain.

This milestone does not qualify planet-scale or unbounded worlds, networking,
distributed databases, GPU residency, or production save compatibility.

Qualification decision `TQP-D031` retains upstream commit `ecf9e33`, native
contract hash `2b3da9885262e7548e95192e698eb00eebe57fadc82e05aa05b5da83dbc2c689`,
and a seven-run Windows benchmark. The 299,520
declared pages require zero explicit runtime catalog entries and a 40-byte
implicit hierarchy descriptor. Central construction and a finite-boundary carve
compact to a sparse overlay, reopen with identical authoritative samples and
regenerated geometry, migrate, and fail closed under descriptor, manifest,
publication, hierarchy, and capacity negative controls. The separate `@tool`
observatory validates both source startup and compact/reopen workflows while
exposing declared, overlay, cache, resident, queue, resource, and hierarchy-query
counters. `TQP-F002` closes only for this retained sparse procedural snapshot
profile; generic production save compatibility remains unqualified.

### TQP-43: Fault Injection And Cross-Order Determinism

Status: `qualified`. Owner: Terrain Systems Lab. Depends on: TQP-15, TQP-17,
TQP-26, TQP-34, TQP-35, TQP-36, TQP-37, TQP-39, TQP-40, TQP-41, TQP-42.

Complete when randomized worker completion, cancellation, duplicate and stale
requests, save interruption, malformed input, allocation failure, rapid viewer
motion, and shutdown produce deterministic authoritative state or a declared
fail-closed error. Resource and event traces must identify the first divergent
generation.

Qualification decision `TQP-D032` retains upstream commit `f4abd7a`, native
contract hash `4cfe12662b60691f93eda8a27d20e1c978e9bab58c2c144b323750d2f39316bf`,
and 15 measured Windows debug runs of 64 completion-order shuffles. The native
authority covers cancellation/replacement, duplicate and stale completion,
explicit page-buffer and snapshot-workspace allocation admission failure,
interrupted publication, malformed output/descriptor, clean shutdown, and a
negative-control trace whose first divergent generation is 4. Debug and release
native authority hashes agree.

The Godot runtime reference stages rapid viewer supersession, proves a complete
viewer lifecycle drain, republishes one canonical final demand, rejects a stale
revision asynchronously, and retains identical non-empty active-state and mesh
signatures for three motion histories. The separate `@tool` observatory exposes
the native fault matrix, generation trace result, coalesced/rejected events,
queues, resources, and forward-versus-reverse replay identity. Controlled
admission failpoints are used because this native build disables C++ exceptions;
arbitrary operating-system out-of-memory recovery is not claimed.

### TQP-44: Complex Terrain Visual And Temporal Corpus

Status: `qualified` for the retained Windows corpus. Owner: Material and
Surface Lab and Terrain Systems Lab.
Depends on: TQP-23, TQP-25, TQP-26, TQP-31, TQP-35, TQP-37, TQP-38, TQP-39,
TQP-40, TQP-43.

Complete when fixed stills and motion paths recursively inspect representative
and adversarial terrain at overview, chunk, transition, and cell scales from
multiple angles. Human review must cover silhouettes, cracks, overlaps,
popping, flicker, shadows, texture scale, edited surfaces, caves, overhangs,
and visual pleasantness against declared targets; automation cannot accept the
milestone by itself.

The retained automation fixes 25 stills, seven motion paths, twelve live source
scenes, four inspection scales, multiple angles, and corpus hashes. The
`@tool` review observatory records no acceptance until a human checks every
declared category, traverses every still and motion path, and requests every
live source scene. The retained verdict is tied to the exact corpus hash.

### TQP-45: Streaming Priority And Fast-Arrival Edit Responsiveness

Status: `qualified` for the retained bounded Windows debug envelope.
Owner: Terrain Systems Lab and Edit Semantics Lab. Depends on: TQP-15, TQP-19,
TQP-22, TQP-27, TQP-35, TQP-36, TQP-37, TQP-39, TQP-40, TQP-42, TQP-43,
TQP-44.

Complete when high-speed traversal and teleports into cold, warm, edited, and
previously evicted regions prove explicit demand classes, bounded queues,
generation-aware cancellation, local-work priority, and starvation limits.
Input acknowledgement, first correct visual response, required collision
coherence, and complete local settlement for digging and construction must be
reported as p50/p95/p99/worst latency. Old distant work must not delay current
local demand, and readiness must be observable instead of inferred from a
temporarily stale render or collision state.

The Windows candidate covers cold, warm, edited, previously evicted, and
superseded destinations. It retains p50/p95/p99/worst acknowledgement, visual,
collision, and settlement latency and exact canonical final-demand identity.
Readiness retains separate order-independent visual and collision leaves and
rejects stale nonzero or staged sink generations; generation zero is accepted
only as the native sink representation of an applied empty payload.

### TQP-46: Targeted Collision Residency And Update Latency

Status: `qualified` for the retained bounded Windows envelope.
Owner: Terrain Systems Lab. Depends on: TQP-24, TQP-35, TQP-36, TQP-37,
TQP-39, TQP-40, TQP-45.

Complete when render, collision, navigation, and authoritative query demand are
independent. Bounded player, vehicle, awake-body, and explicit-query invokers
must maintain a declared swept-motion safety envelope with hysteresis while
distant visible terrain remains collision-free by default. Generation,
main-thread application, replacement, edit coherence, retirement, memory, and
physics cost must be measured, and no qualified path may expose a collision
hole or stale collision inside its declared envelope.

The native policy intentionally gives a visual viewer bounded near-field
collision using activation/deactivation hysteresis; distant visible chunks are
collision-free. Separate collision viewers add collision-only overlays for the
four invoker classes. The candidate checks event consumption, swept overlap,
physics rays, edit replacement, on-demand navigation derivation, and overlay
retirement after canonical visual replanning. Required render and collision
states also prove current-or-empty applied sink generations with no staged
replacement.

### TQP-47: Large-World Rendering, Frame Pacing, Memory, And Queues

Status: `qualified` for the retained bounded Windows debug regression envelope.
Owner: Terrain Systems Lab and Material and Surface Lab. Depends on: TQP-04,
TQP-20, TQP-22, TQP-26, TQP-27, TQP-30, TQP-31, TQP-35, TQP-38, TQP-40,
TQP-42, TQP-45, TQP-46.

Complete when representative large horizontal and vertical terrain workloads
measure frame p50/p95/p99/worst, stutter bursts, render-thread and main-thread
cost, terrain GPU time, draw and triangle counts, worker throughput, queue age
and depth, resident and peak CPU/GPU memory, resource retirement, and loading
state. Traversal, flight, caves, LOD churn, teleports, digging, construction,
and idle steady state must remain bounded by declared profiles. Optimizations
must be individually measured and must preserve all applicable geometry,
material, edit, collision, and persistence evidence.

The reference workload renders a 2048x256x2048 catalog at 1280x720 in
Forward+, with bounded LOD2/LOD1/LOD0 residency. Each of eight workload classes
retains 120 frame samples plus measured render CPU/GPU time, draw and primitive
counts, native worker deltas, queues, loading state, resources, and CPU/GPU
memory. Every scenario retains applied-generation agreement. Its ceilings are
debug-machine regression bounds, not release targets.

### TQP-48: Low-Power Performance Profiles And 60 FPS At 16 W

Status: `qualified` for the retained exact Windows GPU-board WPF60 baseline protocol; the full low-power target pass remains unqualified.
Owner: Terrain Systems Lab and Terrain Qualification Program. Depends on:
TQP-04, TQP-27, TQP-38, TQP-39, TQP-45, TQP-46, TQP-47.

Complete when low-power, balanced, and quality profiles have frozen settings,
hardware, renderer, resolution, view distance, collision policy, warmup,
thermal state, sample count, and the GPU-board WPF60 boundary. The retained CPU
reference must run the exact 60 FPS / 16 GPU-board WPF60 candidate workload and
report frame pacing, arrival and edit latency, collision latency, CPU/GPU time,
memory, GPU-board power, GPU-board energy per frame, and GPU-board energy per
published chunk. The retained 2026-08-08 run completed the exact protocol with 108000 frames,
1802.580076 measured seconds, average GPU-board WPF60 7.138897319856603,
and drift PASS. It is still `MEASURED_TARGET_MISS` because frame_p95,
frame_worst, edit_visual_response, and edit_collision_coherence missed their
targets. Those misses are valid baseline evidence; they cannot be rewritten as
a full low-power pass or used to preselect GPU implementation.

Low-power, balanced, and quality settings are frozen. The exact runner accepts
only `nvidia-smi power.draw` as the inherited WPF60 target source. CPU-package,
battery, DC-input, and AC-input power can be retained as separately labeled
observations when trusted sensors exist, but they cannot close the WPF60 claim
or be inferred from GPU-board watts. The low-power candidate requires a
300-second warmup, 1800 measured seconds, at least 108000 frames, and continuous
GPU-board samples. Shortened, wrong-profile, partial-workload,
discontinuous-power, or missing-sample runs are `INCOMPLETE_RUN`, never target
misses. The exact report retains time-aligned power samples, real
dig/construction and collision-invoker actions, resource retirement, focused
responsiveness evidence, and rolling drift windows.

### TQP-49: Complex Adaptive Terrain Soak And Recovery

Status: `qualified`. Owner: Terrain
Systems Lab. Depends on: TQP-13, TQP-15, TQP-16, TQP-26, TQP-27, TQP-34,
TQP-41, TQP-42, TQP-43, TQP-44, TQP-45, TQP-46, TQP-47, TQP-48.

Complete when repeated cold/warm generation, long traversal, teleports, LOD
churn, digging, construction, material edits, persistence, restart, resource
pressure, controlled failures, recovery, and shutdown retain exact state and
geometry while memory, queues, latency, frame pacing, temperature, and power do
not drift outside declared limits. Reports must retain workload signatures,
provenance, distributions, peak values, recovery traces, and minimized repros
for every failure.

The fail-closed evaluator composes the native 60-second churn, large-world
soak, persistence/restart, fault recovery, TQP-44 review, TQP-45 through TQP-47
focused reports, and the exact TQP-48 long run. Missing review, power, thermal,
memory, queue, or frame-drift evidence remains a named blocker. First/last
steady-state bands must keep memory, frame p99, queue depth, accepted-boundary
power, and GPU temperature within declared drift limits.

### TQP-50: Native Adaptive Terrain Authority Gate

Status: `qualified`, Gate E promoted for the declared bounded Windows CPU envelope. Owner: Terrain Qualification Program.
Depends on: TQP-28 through TQP-49.

Complete when every Phase 4 milestone is qualified for one coherent declared
CPU envelope, all open findings have explicit disposition, independent and
visual reviews pass, reports reproduce from pinned revisions, and the authority
matrix states exactly what world-transvoxel, Cell Lab, and Terrain Lab do and
do not prove. Only this milestone may promote Gate E.

The retained gate report contains the complete milestone matrix, pinned
manifest hash, finding dispositions, and explicit authority boundaries for
world-transvoxel, Cell Lab, Terrain Lab, and the integration game. It cannot
promote while any matrix member is missing or unqualified. The retained
revision-38 report promotes Gate E with no blockers after TQP-48 exact baseline
evidence and TQP-49 soak/recovery both passed their closure conditions.

## Phase 5: Standalone CPU Production Terrain Release

This phase creates and qualifies the separate `world-transvoxel-terrain` addon
from the Gate E CPU reference. The release remains deliberately smaller than a
game framework and has no runtime dependency on either lab.

Execution order: TQP-51 -> TQP-52 -> TQP-53 -> TQP-54 -> TQP-55 -> TQP-56 ->
TQP-57.

Gate E and TQP-51 through TQP-54 are qualified. This phase is the active
production wave and continues with the TQP-55 CPU release matrix.

### TQP-51: Production Addon Boundary

Status: `qualified`. Owner: `world-transvoxel-terrain`. Depends on: Gates A
through E.

Complete when runtime ownership, dependencies, threading, data and resource
lifetimes, extension points, errors, unsupported behavior, and the boundary
between `world-transvoxel` primitives and production terrain orchestration are
frozen. The addon must use the pinned native authority and must not contain a
second fallback mesher or depend on lab presentation state.

The retained Windows qualification pins `world-transvoxel-terrain` commit
`fcf7aa04adb2bf3bcd97bfcfe2b72dc235767cb5`, addon tree
`70f4b0844ce5cab9de9775aebaa91ccb6a4f4e70`, and `world-transvoxel` authority
commit `f4abd7ab4f921f98aba4ee45b4453af0bae53cd8`. The candidate freezes ownership,
threading, lifetimes, extension points, fail-closed errors, and unsupported
scope; all sixteen static validators and retained A4, A5, and A6 Godot
regression reports pass. This qualifies only the candidate package boundary.
Runtime API/profile readiness, production textures and authoring, downstream
migration, release certification, GPU work, and gameplay remain unqualified.

### TQP-52: Runtime API, Configuration Profiles, And Readiness States

Status: `qualified`. Owner: `world-transvoxel-terrain`. Depends on: TQP-15,
TQP-16, TQP-19, TQP-22, TQP-24, TQP-45, TQP-46, TQP-47, TQP-48, TQP-51.

Complete when world/viewer lifecycle, field and edit submission, streaming,
queries, save/load, quality profiles, budgets, and diagnostics have stable APIs.
Render, edit, collision, and query readiness must be explicit and
generation-aware, with bounded back-pressure and cancellation behavior. Every
profile must expose its resolution, distance, queue, memory, collision, and
power tradeoffs without weakening correctness.

The retained Windows candidate at `world-transvoxel-terrain` commit
`4e2f05c397755afd26df93738d40870032bbeaff`, addon tree
`1ca9f2625e0c54c41470086aedde2e4862d0fc4e`, exposes public API version 2,
four immutable built-in profiles, separate generation-aware render, collision,
edit, and query readiness, bounded viewer/request admission, monotonic viewer
revisions, and cancellation of stale generation work. Godot 4.6.3 and 4.7
runtime smokes pass. Profile power fields remain declared intent rather than a
measured power claim, and release qualification remains outside this scope.

### TQP-53: Authoring And Inspection Workflow

Status: `qualified`. Owner: `world-transvoxel-terrain`. Depends on: TQP-08,
TQP-10, TQP-11, TQP-12, TQP-13, TQP-17, TQP-21, TQP-23, TQP-26, TQP-37,
TQP-38, TQP-44, TQP-51, TQP-52.

Complete when brushes, construction, material authoring, previews, undo/redo,
imports, diagnostics, profiling, readiness inspection, and one-action repro
export support real editor and runtime workflows without embedding Terrain Lab
as a production dependency.

The same pinned candidate provides a production Terrain dock, sphere and box
draft previews, carve, construction, fill, paint, restore, and volume-placement
operations, profile import/export, readiness diagnostics, and canonical repro
export. Draft and resource-assignment undo/redo are qualified; committed
append-only terrain edits deliberately make no unsupported inverse claim. The
generic eight-layer material path consumes native weighted material payloads,
and both retained Godot engines pass without a lab runtime dependency,
fallback mesher, or duplicate procedural field.

### TQP-54: Downstream Integration And Migration

Status: `qualified`. Owner: `world-transvoxel-terrain` and Integration game.
Depends on: TQP-16, TQP-27, TQP-41, TQP-42, TQP-49, TQP-51, TQP-52, TQP-53.

Complete when a pinned integration-game revision uses only the candidate addon,
representative terrain, edits, saves, rendering, collision, and failure cases
reduce to canonical evidence, and old saves and configurations have explicit
migration or rejection behavior. Integration defects must become minimized lab
repros before any upstream correction is accepted.

The retained migration pins integration commit
`2103c3eaec02b6bba2af9edbcb21f6275d0f4b4e`, the candidate commit and tree
above, and `world-transvoxel` commit
`f4abd7ab4f921f98aba4ee45b4453af0bae53cd8`. Exact package digests cover 87
candidate files and 173 authority files. Godot 4.6.3 and 4.7 imports and
runtime smokes pass render, collision, edit, journal replay, generation, and
fail-closed behavior. Game-specific presentation and deep topology diagnostics
now live outside the production-addon namespace. The terminated unbounded deep
profile attempt is explicitly excluded from pass evidence, and this milestone
makes no release claim.

### TQP-55: CPU Production Release Qualification Matrix

Status: `blocked`. Owner: Terrain Qualification Program. Depends on: TQP-48,
TQP-49, TQP-51, TQP-52, TQP-53, TQP-54.

Complete when supported platforms, renderers, native artifacts, hardware
classes, editor/runtime modes, upgrade paths, visuals, latency, frame pacing,
memory, collision residency, power profiles, and explicitly unsupported scope
form a reproducible CPU release bundle.

### TQP-56: CPU Production Long-Haul Certification

Status: `blocked`. Owner: Terrain Qualification Program. Depends on: TQP-55.

Complete when extended traversal, flight, editing, construction, save/load,
streaming, origin shifting, fault injection, recovery, and shutdown pass the
release matrix without correctness, memory, queue, performance, thermal, or
power drift.

### TQP-57: CPU Production Terrain Standard And Standalone Release

Status: `blocked`. Owner: Terrain Qualification Program and
`world-transvoxel-terrain`. Depends on: TQP-56.

Complete when the reviewed CPU evidence bundle, versioned standard, standalone
addon package, migration notes, supported matrix, and explicit unqualified
scope are reproducible from pinned revisions. This closes Gate F and is the
first production terrain release; later GPU and game-system work cannot revise
its evidence silently.

## Phase 6: GPU Backend Qualification And Release

This phase starts only after the CPU production release. It evaluates GPU
acceleration against the same field, primitive, terrain, latency, power, and
release contracts without replacing CPU authority by assumption.

Execution order: TQP-58 -> TQP-59 -> TQP-60 -> TQP-61 -> TQP-62 -> TQP-63 ->
TQP-64.

TQP-58 is specified. Implementation milestones remain blocked until concrete
GPU targets and a qualified CPU release exist.

### TQP-58: GPU Architecture Decision

Status: `specified`. Owner: Backend Qualification Lab. Depends on: Gate F.

Complete when field evaluation, meshing, buffer residency, rendering,
collision readback, synchronization, target APIs, and expected benefit are
separate measured decisions. CPU and GPU candidates must run identical pinned
profiles, and promotion requires a material frame-pacing, throughput, or
energy-efficiency benefit without correctness regression.

### TQP-59: GPU Field Evaluation

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-07,
TQP-08, TQP-12, TQP-28, TQP-29, TQP-58.

Complete when GPU density, gradients, materials, edits, filtering, precision,
and determinism pass analytical and CPU differential evidence.

### TQP-60: GPU Meshing Candidate

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-31,
TQP-33, TQP-34, TQP-58, TQP-59.

Complete when GPU regular, transition, and assembled adaptive-terrain
extraction exists as a candidate without weakening the native CPU reference.

### TQP-61: CPU/GPU Differential Corpus

Status: `blocked`. Owner: Backend Qualification Lab and Cell Lab. Depends on:
TQP-34, TQP-50, TQP-60.

Complete when topology, seams, feature survival, materials, edits, bounds,
publication order, and numeric tolerances pass shared primitive and terrain
corpora, including retained negative controls and minimized divergences.

### TQP-62: GPU Residency And Publication

Status: `blocked`. Owner: Backend Qualification Lab and Terrain Systems Lab.
Depends on: TQP-15, TQP-22, TQP-35, TQP-40, TQP-43, TQP-46, TQP-47, TQP-60.

Complete when allocation, reuse, indirect drawing, transfer, versioned
publication, targeted collision readback, stale work, synchronization, queue
budgets, and device-loss recovery are qualified.

### TQP-63: Cross-Hardware GPU Matrix

Status: `blocked`. Owner: Backend Qualification Lab. Depends on: TQP-04,
TQP-48, TQP-61, TQP-62.

Complete when correctness, reproducibility, performance, memory, drivers,
vendors, graphics APIs, power boundaries, thermal steady state, and explicitly
unsupported hardware are recorded for every supported GPU profile.

### TQP-64: GPU Production Terrain Backend Release

Status: `blocked`. Owner: Backend Qualification Lab and
`world-transvoxel-terrain`. Depends on: TQP-58 through TQP-63.

Complete when the GPU backend passes the production addon API, differential,
large-world, responsiveness, collision, power, hardware, migration, recovery,
and packaging matrix. Its release must retain the CPU reference and identify
backend-specific qualified and unsupported scope. This closes Gate G.

## Phase 7: Post-Release Game Systems

This phase contains useful but game-oriented terrain consumers. It cannot
delay or redefine the CPU or GPU terrain releases, and it begins only after
Gates F and G.

Execution batches: (TQP-65, TQP-66, TQP-67, TQP-68, TQP-69) -> TQP-70 ->
TQP-71.

Reference behavior exists for TQP-65 through TQP-70, but it remains
unqualified. Networking remains blocked until a concrete multiplayer authority
model exists.

### TQP-65: Explosion Corpus

Status: `implemented`. Owner: Edit Semantics Lab and Structural and World
Systems Lab. Depends on: Gates F and G, TQP-09 through TQP-14, TQP-17.

Complete when radial and directed blasts, material damage, bounded noise,
overlap, fragmentation inputs, collision timing, replay, and cost are
qualified.

### TQP-66: Connectivity And Support

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gates F and G, TQP-02, TQP-11, TQP-12.

Complete when anchors, solid connectivity, support graphs, floating terrain,
material strength, and under-resolved supports have deterministic policies.

### TQP-67: Fluids And Hydrology

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gates F and G, TQP-05, TQP-16, TQP-19.

Complete when terrain-water intersections, coastlines, caves, drainage,
flooding, edits, LODs, persistence, and rendering have defined ownership.

### TQP-68: Vegetation And Object Placement

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gates F and G, TQP-08, TQP-16, TQP-19.

Complete when placement provenance, invalidation, regeneration, persistence,
collision, and destruction after terrain edits are deterministic.

### TQP-69: Roads, Structures, And Authored Terrain

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gates F and G, TQP-08, TQP-11, TQP-16.

Complete when stamps, foundations, tunnels, bridges, authored construction,
procedural fields, edits, materials, and LODs compose predictably.

### TQP-70: Collapse And Debris

Status: `implemented`. Owner: Structural and World Systems Lab. Depends on:
Gates F and G, TQP-24, TQP-65, TQP-66.

Complete when separated components, collapse decisions, rigid-body conversion,
remeshing, collision, cleanup, persistence, and replay are qualified.

### TQP-71: Networking And Recovery

Status: `blocked`. Owner: Production terrain and integration layers. Depends
on: Gates F and G, TQP-13, TQP-16, TQP-17, TQP-41, TQP-43.

Complete when replication, ordering, conflict resolution, late join, save
recovery, disconnects, corruption, and authority transitions are qualified for
the declared multiplayer model.

## Current Program State

The program records every milestone at a truthful evidence state:

- `TQP-01` through `TQP-50` are qualified
  for their narrow contract, native Windows reference, or reference-model
  scopes. Gate B is qualified; its native chunk rebuild benchmark remains a
  background/debug reference and is not a production frame-time claim.
- `TQP-28` through `TQP-43` qualify the deterministic field contract, bounded
  LOD0 complex native corpus, finite adaptive selector, and static native
  transition-assembly matrix, bounded boundary/enclosure policy, and independent
  geometry/topology oracles, seeded adversarial/minimized repro corpus, and
  bounded native dynamic LOD publication with temporal ownership checks, and
  exact native edit invalidation with incremental remeshing, and bounded native
  adaptive digging/construction semantics with lifecycle and refinement
  identity, adaptive material payload continuity, and bounded native
  render/collision/query/physics agreement with consumer-derived navigation,
  multi-layer LOD2/LOD1/LOD0 streaming/residency, and bounded native-baked
  adaptive persistence with fresh-runtime replay and supported compaction, and
  the retained implicit procedural hierarchy with sparse large-world snapshot
  overlays, plus retained fault injection, fail-closed recovery controls,
  generation-aware traces, and cross-order runtime convergence. `TQP-44`
  through `TQP-47` additionally qualify the accepted visual corpus, bounded
  responsiveness, targeted collision, and large-world rendering regression
  envelope. `TQP-48` now retains the exact GPU-board WPF60 baseline run,
  `TQP-49` passes the complex adaptive soak/recovery aggregation, and `TQP-50`
  closes Gate E for the bounded Windows CPU authority envelope.
- `TQP-51` through `TQP-54` qualify the pinned standalone CPU candidate
  boundary, runtime contract, authoring workflow, and downstream migration;
  `TQP-55` through `TQP-57` remain blocked release work.
- `TQP-58` is the specified CPU-primary GPU architecture decision; `TQP-59`
  through `TQP-64` are blocked GPU implementation and release work.
- `TQP-65` through `TQP-70` retain the previously implemented but unqualified
  destruction and structural reference behavior under revision-34 identifiers.
- `TQP-71` networking remains blocked by a missing multiplayer authority model.

The next dependency-ordered milestone is TQP-55, CPU Production Release
Qualification Matrix. TQP-51 through TQP-54 establish the standalone candidate
boundary, runtime and authoring contracts, and exact downstream migration
without either lab at runtime. Release certification, the low-power target
misses, GPU backend, and game-system behavior remain outside the qualified
claim. A milestone may advance only when its declared evidence passes.

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
invalidation and incremental remeshing mechanics. TQP-37 through TQP-41 now
qualify bounded adaptive edits, material continuity, system agreement,
streaming, persistence, and replay. TQP-42 now qualifies the hierarchy and
snapshot representation at the retained large-world scale. TQP-43 now qualifies
its bounded fault injections and schedule-order convergence. These milestones determine
whether the correct static primitive stays correct while a viewer moves,
terrain changes, and most of the world remains nonresident.

TQP-44 through TQP-49 now provide six separate closure layers instead of one
overloaded performance milestone. They cover recursive visual and temporal
inspection; scheduler priority and fast-arrival edit response; targeted
collision residency and update latency; large-world rendering, frame pacing,
memory, and queues; the exact low-power profiles including the 60 FPS / 16 W
GPU-board WPF60 candidate with target misses retained; and long-running soak and recovery. Spatial or temporal milestones
must expose focused `@tool` observatories and reproducible captures for human
inspection, but screenshots remain supporting evidence and cannot replace
machine invariants or retained reports.

TQP-50 is Gate E. It can qualify only a coherent CPU envelope in which all
earlier Phase 4 contracts agree. Passing it means that the lab has an
authoritative bounded reference for native adaptive edited Transvoxel terrain;
it does not by itself publish a production addon.

TQP-51 through TQP-57 then create, integrate, certify, and release the separate
standalone CPU production addon. TQP-58 through TQP-64 evaluate and release GPU
acceleration only after that CPU baseline exists. TQP-65 through TQP-71 keep
explosions, support, fluids, vegetation, authored structures, collapse, and
networking out of the critical terrain-standardization path. This order makes
the release target explicit while preventing game systems or experimental GPU
work from obscuring terrain-core evidence.

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
  `TQP-D017` and `TQP-D030` retain the later unqualified-phase migrations.
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
  former TQP-28 through TQP-45 native adaptive-terrain qualification phase,
  shift only unqualified later work, and freeze destruction, GPU, and
  production promotion until Gate E passes; `TQP-D030` subsequently inserts
  the new TQP-42 storage milestone and shifts its later identifiers.
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
- `TQP-D025`: qualify TQP-37 for bounded Windows native LOD1/LOD0 adaptive
  digging and construction with exact live-interface topology, authoritative
  field identity across lifecycle actions, under-resolved refinement followed
  by native edit-LOD retention, and reconstructive command-ledger history;
  retain generic in-place undo, adaptive materials, production collision
  residency, low-power performance, deeper LOD, GPU, and production authority
  as unqualified.
- `TQP-D026`: qualify TQP-38 for bounded Windows native adaptive material
  payload continuity, authoritative paint/construction samples, shared-position
  identity through topology-changing LOD replacement, and the retained
  diagnostic shader/capture contract while leaving production materials,
  texture streaming, performance, deeper LOD, and other platforms unqualified.
- `TQP-D027`: qualify TQP-39 after the lab proved that the upstream default
  collision cap removed valid cave/crater triangles and world-transvoxel commit
  `7ef7896` corrected it; retain bounded same-generation render/collision/query,
  physics-ray, targeted-demand, staged replacement, and consumer-derived
  navigation evidence while leaving production collision, navigation,
  performance, deeper LOD, GPU, and production authority unqualified.
- `TQP-D028`: qualify TQP-40 for the retained native Windows LOD2/LOD1/LOD0
  multi-layer streaming and residency profile without claiming native floating
  origin, production performance, or GPU residency.
- `TQP-D029`: qualify TQP-41 for the retained 44-page native-baked adaptive
  persistence profile while keeping direct pre-compaction distant coarse-page
  meshing and large-volume compaction explicitly unqualified.
- `TQP-D030`: insert sparse hierarchy storage and large-world compaction as
  TQP-42, renumber former TQP-42 through TQP-64 to TQP-43 through TQP-65, and
  require measured evidence rather than mandating an octree by assumption.
- `TQP-D031`: qualify TQP-42 for the retained Windows implicit procedural
  hierarchy and sparse-overlay large-world compaction profile, close `TQP-F002`
  only for that profile, and leave production save compatibility unqualified.
- `TQP-D032`: qualify TQP-43 for the retained Windows native fault-order matrix,
  explicit fail-closed admission controls, generation-aware divergence trace,
  and non-empty cross-order Godot runtime convergence after a proven viewer
  lifecycle drain; leave exhaustive schedules, arbitrary OOM recovery,
  non-Windows behavior, visual acceptance, soak, and Gate E unqualified.
- `TQP-D033`: preserve every TQP-01 through TQP-43 qualified claim, expand
  adaptive-terrain closure into TQP-44 through TQP-50, place the standalone CPU
  production release at TQP-51 through TQP-57, place GPU qualification and
  release at TQP-58 through TQP-64, and defer the existing game-oriented work
  to TQP-65 through TQP-71 without advancing any evidence state.
- `TQP-D034`: implement the complete TQP-44 through TQP-50 CPU-authority
  closure toolchain while leaving every milestone unqualified until its ordered
  dependencies and retained evidence pass.
- `TQP-D035`: accept the explicit human PASS for the exact TQP-44 corpus and
  promote TQP-44 through TQP-47 in dependency order for their bounded Windows
  scopes; retain TQP-48 through TQP-50 and Gate E as unqualified.
- `TQP-D036`: correct TQP-48's inherited `60 FPS / 16 W` target to the
  `gpu-marching-cubes` GPU-board WPF60 definition using `nvidia-smi power.draw`;
  keep CPU-package, battery, DC-input, and AC-input power as separate
  observation boundaries and leave TQP-48 through TQP-50 unqualified until
  exact retained evidence exists.
- `TQP-D037`: accept the exact TQP-48 GPU-board WPF60 baseline as retained
  evidence, keep its target misses explicit, promote TQP-49 and TQP-50 from
  fail-closed reports, and close Gate E only for the bounded Windows CPU
  adaptive-terrain authority envelope.
- `TQP-D038`: qualify the pinned TQP-51 standalone candidate-addon boundary,
  retain `world-transvoxel` as sole native terrain authority, and leave TQP-52
  and every later production, integration, release, GPU, and gameplay claim
  unqualified.
- `TQP-D039`: qualify TQP-52 through TQP-54 for the pinned Windows candidate
  runtime, bounded production authoring workflow, and exact downstream
  migration while leaving TQP-55 and all release claims fail-closed.
