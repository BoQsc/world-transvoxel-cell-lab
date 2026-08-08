# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo. It owns controlled research and evidence for the Terrain
Qualification Program; it does not own production implementation and does not
extend the Cell Lab root node.

The [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md) is the
single human-readable roadmap. Program revision 33 contains TQP-01 through
TQP-65 in ground-up execution order:

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
  and cross-order runtime convergence; TQP-44 through TQP-46 remain proposed;
- TQP-47 through TQP-52 retain implemented but unqualified destruction and
  structural reference behavior;
- TQP-53 is the specified CPU-primary GPU architecture decision;
- TQP-54 through TQP-65 remain blocked GPU or production work.

The next milestone is TQP-44, Complex Terrain Visual And Temporal Corpus. It
requires explicit human review and cannot be accepted by automation alone.
Gate E remains closed, so the lab does not claim that complex dynamic adaptive
Transvoxel terrain is qualified yet.

The [What Comes Next](TERRAIN_QUALIFICATION_PROGRAM.md#what-comes-next)
section explains the broader path: define the adaptive hierarchy, prove
mixed-resolution geometry independently, qualify dynamic edits and streaming,
perform visual and performance review, and only then consider Gate E. Later
destruction, GPU, and production phases remain deliberately separate.

`qualification_state.json`, `program_blockers.json`, and retained reports are
machine evidence mirrors. They cannot widen the TQP claim.
