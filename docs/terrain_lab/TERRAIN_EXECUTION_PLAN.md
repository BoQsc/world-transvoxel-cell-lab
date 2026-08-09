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

The current action is the CPU Finalization Precondition recorded inside the
TQP: CPU-C1, then CPU-C2, then CPU-C3. `TQP-58` remains the next numbered
milestone, but it is blocked and cannot be implemented or promoted until that
precondition passes.

Validate the mirror with:

```text
python labs/terrain_lab/tools/validate_execution_plan.py
```
