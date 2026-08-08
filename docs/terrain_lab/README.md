# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo. It owns controlled research and evidence for the Terrain
Qualification Program; it does not own production implementation and does not
extend the Cell Lab root node.

The [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md) is the
single human-readable roadmap. Program revision 36 contains TQP-01 through
TQP-71 in ground-up execution order:

- TQP-01 through TQP-43 are qualified only for their declared bounded scopes;
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
- TQP-48 through TQP-50 are implemented but remain unqualified in dependency
  order;
- TQP-51 through TQP-57 are the blocked standalone CPU production release;
- TQP-58 is the specified CPU-primary GPU architecture decision and TQP-59
  through TQP-64 are the blocked GPU qualification and release;
- TQP-65 through TQP-70 retain implemented but unqualified post-release game
  systems, while TQP-71 networking remains blocked.

The next promotion milestone is TQP-48, Low-Power Performance Profiles And
60 FPS At 16 W. It requires an accepted package or complete-system power
boundary. Gate E remains closed, so the lab does not claim that complex dynamic
adaptive Transvoxel terrain is fully qualified yet.

The [What Comes Next](TERRAIN_QUALIFICATION_PROGRAM.md#what-comes-next)
section explains the broader path: finish visual, responsiveness, targeted
collision, rendering, power, and soak evidence; close Gate E; release the
standalone CPU addon; qualify and release GPU; and only then advance
game-oriented systems.

`qualification_state.json`, `program_blockers.json`, and retained reports are
machine evidence mirrors. They cannot widen the TQP claim.
