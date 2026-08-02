# World Transvoxel Terrain Lab

The Terrain Lab is a separate experimental addon inside the World Transvoxel
Labs monorepo.

It owns controlled research and evidence for the Terrain Qualification Program.
It does not own production implementation, and it does not extend the Cell Lab
root node.

The complete `TQP-01` through `TQP-46` catalog is now executable and
fail-closed. Seventeen milestones are qualified for narrow contract or reference
scopes, fifteen have implemented evidence with named gaps, two are
specified, and twelve GPU or production milestones are blocked by named
external targets.

TQP numbers are stable domain identifiers, not execution order. The separate
[Terrain Execution Plan](TERRAIN_EXECUTION_PLAN.md) is the authoritative,
dependency-ordered work sequence and next-milestone queue.

Gate B (`TQP-06` through `TQP-11`) is qualified. Its evidence includes seven
brush primitives, native digging and construction at LOD0-7, a 240-fixture
resolvability matrix, edit-journal v2 transactions and migration, collision
input agreement, seam checks, deterministic replay, diagnostic cross-sections,
and a 2,048-edit reference soak. `TQP-12` is also qualified for that declared
Windows debug reference workload; it is not a production frame-time claim.

The temporal-integrity wave is also qualified for its Godot 4.7.1 Windows
x86_64 native reference scope. TQP-21 exercises real workers, stale generation
rejection, and atomic render/collision publication. TQP-13 covers temporal
carve/construction ordering and deterministic restart replay. TQP-25 covers
durable journals, truncated-tail recovery, corruption rejection, compaction,
and current plus legacy schema migration. Cross-filesystem guarantees,
networked edit ordering, and automatic stale staging cleanup remain explicit
non-claims.

This is not a production-terrain claim. See `qualification_state.json`,
`program_blockers.json`, and the retained report for exact qualified and
unqualified scope.

See `TERRAIN_QUALIFICATION_PROGRAM.md` for the complete program.
