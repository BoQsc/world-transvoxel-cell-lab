# Cell Lab Preservation Audit

## Decision

The Cell Lab remains the frozen primitive-level Transvoxel qualification
system inside the World Transvoxel Labs monorepo. New production terrain,
streaming, texture, destruction, and GPU-system work belongs to separately
owned Terrain Qualification Program domains.

## Baseline

The preservation comparison uses commit `889766b`, the parent state before the
first physical monorepo conversion commit `ce7da29`.

Audit date: 2026-08-01.

Audit result: `PASS`.

- no original Cell Lab addon file was deleted;
- native case, chunk, edit, reference-field, reference-terrain, authority, and
  qualification behavior retained its locked signatures;
- the standalone project still launches
  `res://labs/cell_lab/scenes/main.tscn`;
- Cell Lab executable sources do not depend on Terrain Lab;
- the pinned `world-transvoxel` source and two native artifacts verified;
- Godot 4.7.1 GL Compatibility, Mobile, and Forward+ smoke lanes passed;
- all Cell Lab validation suites passed;
- all 14 Windows Forward+/D3D12 visual references reproduced with zero changed
  pixels.

The current visual standard is intentionally not byte-identical to the old
11-image baseline. It has 14 reviewed diagnostic views and stricter capture,
scope, and freshness contracts. The qualification standard changed only its
visual count and the bundle hash derived from that evidence; primitive and
terrain correctness signatures did not change.

## Boundary Guard

Run the executable monorepo boundary check with:

```text
python labs/cell_lab/tools/verify_lab_boundaries.py
```

The check fails if executable Cell Lab assets refer to Terrain Lab code, if
executable Terrain Lab assets refer to Cell Lab code, or if the shared project
stops launching the Cell Lab scene by default. Both lab CI workflows run it.

## Change Rule

Cell Lab changes remain appropriate only when they strengthen a primitive
invariant, add a minimized native repro, expand a controlled cell/chunk/seam
corpus, improve primitive observability, retain evidence for an upstream
correction, or qualify a candidate backend against the same primitive
contract.
