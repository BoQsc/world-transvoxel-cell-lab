# Terrain Qualification Execution Plan

This file is a compatibility pointer, not a second roadmap.

Follow [TERRAIN_QUALIFICATION_PROGRAM.md](TERRAIN_QUALIFICATION_PROGRAM.md) in
numeric order. It is the single human-readable authority for scope, status,
dependencies, exit criteria, current position, claim boundaries, and retained
decisions.

`addons/world_transvoxel_terrain_lab/standards/execution_plan.json` is the
machine-readable mirror used to reject missing milestones, duplicates,
backward dependencies, incorrect wave state, and an invalid recommended-next
item. It must not introduce work or ordering absent from the TQP.

CPU-C1 through CPU-C3, TQP-R01 through TQP-R06, and CPU-B1 through CPU-B3 are
qualified under the retained three-logical-CPU boundary. The final CPU
correctness reference is frozen with an explicit performance target miss.
TQP-58 is qualified as a decision-only milestone selecting GPU field evaluation
plus regular and transition meshing as bounded candidates while CPU control
remains authoritative. The late bounded foreground-priority hypothesis was
tested in both run orders and rejected as an automatic production policy; it
does not alter the sequence. Execute TQP-59 next; TQP-60 through TQP-64 remain
blocked on their own evidence.

Validate the mirror with:

```text
python -B labs/terrain_lab/tools/run_with_cpu_limit.py --logical-cpus 3 -- \
  python -B labs/terrain_lab/tools/validate_execution_plan.py
```
