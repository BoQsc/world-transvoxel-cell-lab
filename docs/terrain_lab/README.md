# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo. It owns controlled research and evidence for the Terrain
Qualification Program; it does not own production implementation and does not
extend the Cell Lab root node.

The [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md) is the
single human-readable roadmap. Program revision 38 contains TQP-01 through
TQP-71 in ground-up execution order:

- TQP-01 through TQP-50 are qualified only for their declared bounded scopes;
- TQP-28 through TQP-43 retain the deterministic native field, complex LOD0
  corpus, bounded adaptive selector, native transition-assembly matrix, and
  finite-world boundary/enclosure policy plus independent geometry/topology
  oracles, seeded adversarial replay and minimization, and bounded native
  LOD1/LOD0 dynamic publication, exact edit invalidation, and bounded adaptive
  digging/construction with lifecycle/refinement identity, adaptive material
  continuity, bounded render/collision/query/navigation agreement, bounded
  multi-layer streaming/residency, native-baked persistence/recovery, and the
  retained implicit procedural hierarchy with sparse large-world compaction,
  plus fault injection, fail-closed admission controls, generation-aware traces,
  and cross-order runtime convergence;
- TQP-44 through TQP-47 qualify the accepted Windows visual/temporal corpus,
  bounded fast-arrival responsiveness, targeted collision residency, and the
  bounded large-world rendering regression envelope;
- TQP-48 qualifies the exact GPU-board WPF60 baseline protocol with explicit
  target misses, TQP-49 qualifies complex adaptive soak/recovery, and TQP-50
  closes Gate E for the bounded Windows CPU authority envelope;
- TQP-51 through TQP-57 are the blocked standalone CPU production release;
- TQP-58 is the specified CPU-primary GPU architecture decision and TQP-59
  through TQP-64 are the blocked GPU qualification and release;
- TQP-65 through TQP-70 retain implemented but unqualified post-release game
  systems, while TQP-71 networking remains blocked.

The next promotion milestone is TQP-51, Production Addon Boundary. Gate E is
closed only for the bounded Windows CPU authority envelope; production runtime,
standalone addon packaging, integration migration, full low-power target pass,
GPU backend, and cross-hardware claims remain unqualified.

The [What Comes Next](TERRAIN_QUALIFICATION_PROGRAM.md#what-comes-next)
section explains the broader path: finish visual, responsiveness, targeted
collision, rendering, power, and soak evidence; use the closed Gate E CPU
reference to release the standalone CPU addon; qualify and release GPU; and
only then advance game-oriented systems.

The [Terrain Lab Baselines](BASELINES.md) file records the retained TQP-48
through TQP-50 CPU-authority baseline. Read it before changing performance
budgets, promotion state, or retained reports.

`qualification_state.json`, `program_blockers.json`, and retained reports are
machine evidence mirrors. They cannot widen the TQP claim.
