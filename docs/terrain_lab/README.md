# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo. It owns controlled research and evidence for the Terrain
Qualification Program; it does not own production implementation and does not
extend the Cell Lab root node.

The [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md) is the
single human-readable roadmap. Program revision 46 contains TQP-01 through
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
- TQP-51 through TQP-56 qualify the standalone candidate boundary, runtime,
  authoring, migration, release matrix, and long-haul certification; TQP-57 is
  the historical limited Windows CPU Terrain Standard 1.0 production release;
- the ordered TQP-R01 through TQP-R06 CPU Production Closure qualifies current
  construction ownership, temporal continuity, global coarse coverage,
  LOD0-through-LOD3 refinement, prefetch and targeted collision readiness,
  bounded performance, and a self-contained Godot 4.7 release candidate;
- TQP-58 is specified after both CPU preconditions pass under a hard
  three-logical-CPU ceiling; TQP-59 through TQP-64 remain blocked GPU work;
- TQP-65 through TQP-70 retain implemented but unqualified post-release game
  systems, while TQP-71 networking remains blocked.

The next work is TQP-58, GPU Architecture Decision. Gate F and the bounded CPU
Terrain Standard 1.0 Windows release remain qualified correctness baselines on
the corrected committed-tree basis in `TQP-D042`; `TQP-D043` required CPU
finalization and `TQP-D044` qualifies it without claiming the recorded
production responsiveness targets pass. `TQP-D045` qualifies the six-step
current CPU production closure and self-contained `1.1.0-rc1` bundle without
claiming public Asset Library acceptance. The GPU backend, non-Windows, and
cross-hardware claims remain unqualified.

Godot 4.7 is the minimum and sole current qualification target. Godot 4.6
results are retained only as historical observations; they are not rerun or
treated as a compatibility requirement. Newer Godot versions require an
explicit qualification decision before replacing or expanding the matrix.

The [What Comes Next](TERRAIN_QUALIFICATION_PROGRAM.md#what-comes-next)
section records the completed CPU authority and standalone-release path, the
two qualified CPU preconditions, the eligible TQP-58 decision, and the later
game-oriented systems. The
dependency order remains authoritative even when investigation happens ahead
of promotion.

The [Terrain Lab Baselines](BASELINES.md) file records the retained TQP-48
through TQP-50 CPU-authority baseline, the compact exact performance scorecard,
the process-wide CPU development baseline, and both current CPU readiness
records. Read it before changing
performance budgets, promotion state, or retained reports.

`qualification_state.json`, `program_blockers.json`, and retained reports are
machine evidence mirrors. They cannot widen the TQP claim.
