# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo. It owns controlled research and evidence for the Terrain
Qualification Program; it does not own production implementation and does not
extend the Cell Lab root node.

The [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md) is the
single human-readable roadmap. Program revision 19 contains TQP-01 through
TQP-64 in ground-up execution order:

- TQP-01 through TQP-27 are qualified only for their declared bounded scopes;
- TQP-28 through TQP-45 are the proposed native adaptive-terrain phase now
  required before any authoritative terrain claim;
- TQP-46 through TQP-51 retain implemented but unqualified destruction and
  structural reference behavior;
- TQP-52 is the specified CPU-primary GPU architecture decision;
- TQP-53 through TQP-64 remain blocked GPU or production work.

The next milestone is TQP-28, Field Generation And Sampling Contract. Gate E
remains open, so the lab does not claim that complex adaptive Transvoxel terrain
is qualified yet.

`qualification_state.json`, `program_blockers.json`, and retained reports are
machine evidence mirrors. They cannot widen the TQP claim.
