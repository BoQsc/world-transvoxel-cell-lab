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

CPU-C1 through CPU-C3 and TQP-R01 through TQP-R06 remain qualified under the
retained three-logical-CPU boundary. CPU-B1 retains the reviewed post-correction
human baseline and CPU-B2 retains causal attribution. The current action is
CPU-B3, Cautious Remediation And Exhaustion Review. Change one trace-proven
factor at a time, use trace-off A/B measurements, preserve all correctness and
human regressions, and keep TQP-58 blocked until the independent exhaustion
review passes.

Validate the mirror with:

```text
python -B labs/terrain_lab/tools/run_with_cpu_limit.py --logical-cpus 3 -- \
  python -B labs/terrain_lab/tools/validate_execution_plan.py
```
