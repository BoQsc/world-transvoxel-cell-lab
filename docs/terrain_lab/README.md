# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo.

It owns controlled research and evidence for the Terrain Qualification Program.
It does not own production implementation, and it does not extend the Cell Lab
root node.

The complete `TQP-01` through `TQP-46` catalog is now executable and
fail-closed. Nineteen milestones are qualified for narrow contract or reference
scopes, thirteen have implemented evidence with named gaps, two are
specified, and twelve GPU or production milestones are blocked by named
external targets.

TQP revision 5 numbers are the execution order. Read TQP-01 through TQP-46 in
the [Terrain Qualification Program](TERRAIN_QUALIFICATION_PROGRAM.md); the
[Terrain Execution Plan](TERRAIN_EXECUTION_PLAN.md) is its concise wave index.

Gate B (`TQP-07` plus `TQP-09` through `TQP-13`) is qualified. Its evidence includes seven
brush primitives, native digging and construction at LOD0-7, a 240-fixture
resolvability matrix, edit-journal v2 transactions and migration, collision
input agreement, seam checks, deterministic replay, diagnostic cross-sections,
and a 2,048-edit reference soak. `TQP-14` is also qualified for that declared
Windows debug reference workload; it is not a production frame-time claim.

The temporal-integrity wave is also qualified for its Godot 4.7.1 Windows
x86_64 native reference scope. TQP-15 exercises real workers, stale generation
rejection, and atomic render/collision publication. TQP-17 covers temporal
carve/construction ordering and deterministic restart replay. TQP-16 covers
durable journals, truncated-tail recovery, corruption rejection, compaction,
and current plus legacy schema migration. Cross-filesystem guarantees,
networked edit ordering, and automatic stale staging cleanup remain explicit
non-claims.

The first Wave 02 batch adds separate material-blending, streaming-window, and
large-world coordinate contracts. TQP-19 and TQP-20 are qualified for their
deterministic reference scopes. TQP-18 has 597 exact fixtures and a retained
four-panel visual whose automated checks pass; human visual review remains its
only promotion condition.

This is not a production-terrain claim. See `qualification_state.json`,
`program_blockers.json`, and the retained report for exact qualified and
unqualified scope.

See `TERRAIN_QUALIFICATION_PROGRAM.md` for the complete program.
