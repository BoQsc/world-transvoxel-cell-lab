# Terrain Qualification Execution Plan

The TQP identifiers are stable, domain-grouped catalog identifiers. They are
not an instruction to complete milestones in numerical order.

The authoritative execution order is
`addons/world_transvoxel_terrain_lab/standards/execution_plan.json`. It places
all 46 milestones into dependency-valid waves and ordered steps. A milestone
may be investigated at any time, but it may be completed or promoted only
after every declared dependency occupies an earlier execution step and has the
required evidence state.

## Current Execution State

- `TQP-WAVE-00` is complete: TQP-01 through TQP-12, TQP-15, and TQP-20.
- `TQP-WAVE-01` is complete: TQP-21, TQP-25, and TQP-13 are qualified for
  their declared native Windows reference scopes.
- `TQP-WAVE-02` is active.
- The first active step is TQP-16, TQP-22, and TQP-23.
- GPU and production waves remain blocked by absent candidate implementations.

## Waves

1. Qualified foundations and reference semantics.
2. Temporal integrity and durable publication.
3. Streaming, materials, collision, observability, and large-terrain evidence.
4. Destruction and structural world systems.
5. GPU candidate qualification.
6. Production terrain and release qualification.

Parallel entries inside one step have no dependency on each other. Steps
inside a wave are sequential. The waves are sequential even when later work
could be explored independently, because the plan optimizes for authoritative
promotion and understandable evidence rather than maximum speculative
parallelism.

Validate the plan with:

```text
python labs/terrain_lab/tools/validate_execution_plan.py
```

The validator rejects duplicate or missing TQP identifiers, backward
dependencies, inconsistent active-wave metadata, and completed waves that
contain milestones without qualified or production evidence.
