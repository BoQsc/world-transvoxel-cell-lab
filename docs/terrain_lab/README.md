# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo. It owns controlled research and evidence for the Terrain
Qualification Program; it does not own production implementation and does not
extend the Cell Lab root node.

The [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md) is the
single human-readable roadmap. Program revision 20 contains TQP-01 through
TQP-64 in ground-up execution order:

- TQP-01 through TQP-29 are qualified only for their declared bounded scopes;
- TQP-28 and TQP-29 retain the deterministic native field contract and bounded
  LOD0 complex-field corpus; TQP-30 through TQP-45 remain proposed;
- TQP-46 through TQP-51 retain implemented but unqualified destruction and
  structural reference behavior;
- TQP-52 is the specified CPU-primary GPU architecture decision;
- TQP-53 through TQP-64 remain blocked GPU or production work.

The next milestone is TQP-30, Adaptive LOD Selection And Neighbor Contract. Gate E
remains open, so the lab does not claim that complex adaptive Transvoxel terrain
is qualified yet.

The [What Comes Next](TERRAIN_QUALIFICATION_PROGRAM.md#what-comes-next)
section explains the broader path: define the adaptive hierarchy, prove
mixed-resolution geometry independently, qualify dynamic edits and streaming,
perform visual and performance review, and only then consider Gate E. Later
destruction, GPU, and production phases remain deliberately separate.

`qualification_state.json`, `program_blockers.json`, and retained reports are
machine evidence mirrors. They cannot widen the TQP claim.
