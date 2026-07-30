# Cell Lab Transvoxel Qualification Standard

## Purpose

Milestones 16 through 29 turn the Cell Lab from a collection of useful probes
into a repeatable qualification system. The qualification result answers a
bounded question:

> Does the pinned `world-transvoxel` native backend satisfy the committed
> correctness, terrain, edit, runtime-policy, integration, platform, and
> release evidence contracts?

A `PASS` applies only to the dependency and scope identified by the committed
manifests. It is not proof that every scalar field, platform, GPU, driver, game
runtime, or future upstream revision is correct.

## Authority And Ownership

`world-transvoxel` remains the meshing authority under test. The lab calls
`WorldTransvoxelCellProbe` and production `WtChunkMesher` entry points; it has
no fallback mesher.

The lab independently owns:

- scalar fields, fixtures, edit sequences, and schedules;
- invariants, native-buffer analysis, collision comparisons, and reports;
- standards, visual references, release evidence, and governance records.

The integration game is downstream evidence. Its snapshots can confirm parity
or expose a suspected layer, but they do not redefine native correctness.

## Qualification Layers

The complete run has three focused service layers:

| Layer | Milestones | Evidence |
| --- | --- | --- |
| Correctness qualification | 16-18 | adversarial fields, minimized native repro, interpolation and table properties |
| Runtime qualification | 19-25 | edit stress, scaling, buffer memory, rendering inputs, collision, streaming simulation, persistence |
| Release qualification | 26-29 | integration parity, platform/renderer scope, release bundle, upstream governance |

`wt_cell_lab_qualification_runner.gd` orchestrates these services and compares
their stable signature against `standards/qualification_standard.json`.
`WtTransvoxelCellLab` remains a thin scene-facing facade.

## Locked Results

The current standard requires all 14 milestone statuses to be `PASS`.

- Adversarial qualification: 10 profiles, 20 LOD probes, 21,368 triangles.
- Minimized repro: `coarse_tunnel_roof_alias_v1`, case `124`, cell
  `(5, 4, 8)`, eight samples, two reproduced disagreements.
- Independent checks: 1,536 regular intersections, 4,096 transition
  intersections, 48 orientations, and 384 complement pairs.
- Edit stress: 24 operations and four exact replay checkpoints.
- Scaling: six scenarios and 5,579 triangles.
- Memory: 16 canonical native buffers and 317,516 payload bytes.
- Rendering: 6,473 tangent samples and material IDs `1`, `2`, `3`, `4`, `6`.
- Collision: 11,356 exact mesh faces and nine mesh/SDF queries.
- Streaming: three deterministic schedules and 36 chunk builds.
- Persistence: eight edits with payload corruption rejection and exact reload.
- Integration parity: three fixtures, five operations, two classifications.
- Release: 10 core evidence files and 11 visual standards.
- Governance: one retained case and eight mandatory evidence categories.

Exact hashes and signatures live in the JSON standards and are intentionally
not duplicated here.

## Retained Negative Results

Negative detections are standards, not suppressed failures. They prove that
the validators still detect known limits:

- the coarse tunnel roof aliases at LOD1 and resolves at LOD0;
- four named under-resolved adversarial probes retain their expected interior
  open-edge counts;
- the integration watertightness fixture remains classified instead of being
  converted into an unexplained pass.

Only those named and numerically locked detections are accepted. A new,
missing, or changed detection fails the relevant milestone.

The complement corpus records 137 topology-count asymmetries. Equal triangle
or component counts are not a universal complement invariant, so the lab
measures that property without incorrectly rejecting valid table behavior.

## Platform Scope

Qualified native artifacts:

- Windows/x86_64 debug;
- Windows/x86_64 release.

Declared renderer lanes:

- `gl_compatibility`;
- `mobile`;
- `forward_plus`.

The visual authority baseline is captured on Windows with `forward_plus`.
Automated candidates use the D3D12 rendering driver so hosted Windows runners
can use either a hardware adapter or the Windows software adapter. Candidate
comparison normalizes PNG color representation and applies the committed pixel
thresholds. Other native platform targets listed in
`standards/platform_renderer_matrix.json` remain explicitly unqualified until
their required artifacts and CI executions exist.

## Commands

Run all existing and qualification suites:

```text
godot --headless --path . --script labs/cell_lab/tools/run_cell_lab_validation.gd -- all
```

Run only milestones 16-29:

```text
godot --headless --path . --script labs/cell_lab/tools/run_cell_lab_validation.gd -- qualification
```

Print the measured stable qualification signature:

```text
godot --headless --path . --script labs/cell_lab/tools/print_qualification_standard.gd
```

Run structural and locked-result coverage:

```text
godot --headless --path . --script addons/world_transvoxel_cell_lab/tests/wt_cell_lab_smoke.gd
```

Capture a candidate visual set and compare it:

```text
python labs/cell_lab/tools/run_visual_validation.py --godot path\to\godot.exe
```

## Change Rule

A standards change is acceptable only when the reason is explicit and the
evidence chain remains closed:

1. Preserve a minimal deterministic repro.
2. State the invariant and suspected ownership layer.
3. Demonstrate the old result and the proposed correction.
4. Add focused automated and visual evidence where geometry is involved.
5. Review whether the fix belongs upstream, in the lab, or downstream.
6. Update the locked standard and release bundle intentionally.
7. Re-run native dependency, smoke, qualification, standards, and visual
   checks.

Changing a baseline merely to make a failing run green is not qualification.
