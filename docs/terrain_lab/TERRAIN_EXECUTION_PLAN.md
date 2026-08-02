# Terrain Qualification Execution Plan

TQP revision 5 identifiers are the ground-up execution sequence. Reading
TQP-01 through TQP-46 now follows the program from foundations to release.

The authoritative execution order is
`addons/world_transvoxel_terrain_lab/standards/execution_plan.json`. It places
all 46 milestones into dependency-valid waves and ordered steps. A milestone
may be investigated at any time, but it may be completed or promoted only
after every declared dependency occupies an earlier execution step and has the
required evidence state.

## Current Execution State

- `TQP-WAVE-00` is complete: TQP-01 through TQP-14.
- `TQP-WAVE-01` is complete: TQP-15, TQP-16, and TQP-17 are qualified for
  their declared native Windows reference scopes.
- `TQP-WAVE-02` is active.
- The first Wave 02 step is complete: TQP-18, TQP-19, and TQP-20 are qualified
  for their declared reference scopes.
- TQP-22 in the second step is qualified for its horizontal CPU reference.
- TQP-21 is the only recommended next milestone. Its exact and automated
  evidence passes; explicit human review of the corrected deterministic
  observatory render remains open.
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
dependencies, inconsistent active-wave metadata, completed waves that contain
milestones without qualified or production evidence, and recommended-next
lists that include already qualified entries.
