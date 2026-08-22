# Terrain Lab Results

This directory retains machine-readable Terrain Qualification Program evidence.

All CPU-intensive Python and Godot commands on the qualification host must run
through `labs/terrain_lab/tools/run_with_cpu_limit.py`. It fails closed above
three logical CPUs, pins the parent before launch, and verifies the child
inherited the same affinity. Native builds additionally use `scons -j3`.

## CPU-B2 Causal Trace Evidence

`cpu_human_baseline_trace_readiness_windows.json` pins the integration report
and compact causal slice retained at `world-transvoxel-integration-game` commit
`0950e3d`. CPU-B2 passes only observation and attribution: edited chunks finish
their native and Godot sink work before a relocation-wide visibility barrier,
and observed movement rejection comes from collision readiness during backlog.
The route also has 296 explicitly paired transition-mask starts, successful
finishes, and consumed completions with no mismatch. The largest traced
movement hitch was accepted and remains unresolved.

Tracing is disabled by default and is not a performance baseline. CPU-B3 uses
trace-off A/B runs, changes one causal factor at a time, and retains full
correctness plus human regressions. The superseding 2026-08-23 final CPU
closure qualifies TQP-58 as a decision only; TQP-59 is next.

## CPU Finalization Evidence

`cpu_finalization/manifest.json` digest-pins the 24 reports used by CPU-C1,
CPU-C2, and CPU-C3, including current three-logical-CPU qualification runs and
clearly separated historical failed or rejected experiments.
`cpu_finalization_readiness_windows.json` is rebuilt and checked with:

```text
python -B labs/terrain_lab/tools/retain_cpu_finalization_evidence.py
python -B labs/terrain_lab/tools/run_with_cpu_limit.py --logical-cpus 3 -- \
  python -B labs/terrain_lab/tools/audit_cpu_finalization.py --require-eligible
```

The retained audit reports `PASS` for ordered CPU finalization and `MISS` for
the independent production responsiveness target assessment. TQP-58 eligibility
must never be presented as a 60 Hz, wattage, relocation, settlement, or GPU
qualification claim.

`native_field_reference_windows.json` retains the focused TQP-28 field contract
and TQP-29 fourteen-fixture native LOD0 complex-field corpus:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_native_field_validation.gd -- \
  --output res://labs/terrain_lab/results/native_field_reference_windows.json
```

Use `--fixture <fixture_id>` after the command separator for a minimized
single-fixture repro. This corpus is a Windows debug regression reference; it
does not qualify adaptive LOD selection, transition cells, or production
terrain performance.

`adaptive_lod_reference_windows.json` retains the focused TQP-30 bounded
adaptive hierarchy, hysteresis, origin-shift, teleport, exact-coverage, and
invalid-arrangement evidence:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_adaptive_lod_validation.gd -- \
  --output res://labs/terrain_lab/results/adaptive_lod_reference_windows.json
```

Use `--scenario <scenario_id>` for a focused selector repro. The retained
performance distribution is a Windows debug regression ceiling for the finite
16x16x16-chunk hierarchy, not a production streaming budget.

`transition_assembly_reference_windows.json` retains the focused TQP-31 native
regular/transition matrix:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_transition_assembly_validation.gd -- \
  --output res://labs/terrain_lab/results/transition_assembly_reference_windows.json
```

Use `--fixture <fixture_id>` for any retained face, edge, corner, all-face, or
empty/full minimized repro. The full matrix calls `WorldTransvoxelCellProbe`
directly 658 times with no fallback and retains exact cold/warm signatures.
Its static bounded claim does not include dynamic LOD publication, arbitrary
hierarchies, or production performance.

`boundary_enclosure_reference_windows.json` retains the focused TQP-32 native
boundary and enclosure policy:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_boundary_enclosure_validation.gd -- \
  --output res://labs/terrain_lab/results/boundary_enclosure_reference_windows.json
```

Use `--fixture <fixture_id>` for a closed-volume, closed-terrain, or declared
open-contour repro. The retained report calls `WorldTransvoxelCellProbe` 69
times, records exact cold/warm signatures and all-six-face halo sampling, and
requires twelve invalid-policy controls. The adjacent PNG is the automated
1280x720 editor diagnostic; it is not a visual-quality acceptance gate.

`independent_oracle_reference_windows.json` retains TQP-33 over five native
assemblies and thirteen independently implemented geometry/topology checks:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_independent_oracle_validation.gd -- \
  --output res://labs/terrain_lab/results/independent_oracle_reference_windows.json
```

Use `--fixture <fixture_id>` for a minimized native fixture. The full report
retains 74 direct native calls, thirteen designated injected defects, timing
distributions, memory, provenance, and exact cold/warm signatures. The adjacent
PNG is a diagnostic editor capture, not visual-quality acceptance.

`adversarial_corpus_reference_windows.json` retains the focused TQP-34 seeded
native corpus and deterministic failure minimizer:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_adversarial_corpus_validation.gd -- \
  --output res://labs/terrain_lab/results/adversarial_corpus_reference_windows.json
```

Use `--case <case_id>` for one retained seed or corrected regression and
`--replay-minimized` for the serialized two-triangle duplicate fixture. The
full report executes 28 cold/warm and completion-order replays, 240 direct
native chunk calls, and the TQP-33 independent oracle on every replay. The
first canonical replay for each case uses a fresh native probe and the warm
lane immediately repeats it; neither lane claims hardware-cache isolation. The
adjacent PNG is an editor diagnostic, not visual-quality acceptance; actual
concurrent publication remains outside this milestone.

`dynamic_lod_publication_reference_windows.json` retains the focused TQP-35
native dynamic-publication qualification:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_dynamic_lod_publication_validation.gd -- \
  --output res://labs/terrain_lab/results/dynamic_lod_publication_reference_windows.json
```

The report retains every audited frame across split, merge, replacement,
rapid supersession, stale-result rejection, presentation rebase, teleport,
unload, and deterministic restart. The adjacent motion JSON and four PNGs are
generated by `capture_dynamic_lod_publication_observatory.gd`; they support
inspection but do not replace the zero-hole and zero-overlap machine gates.

`edit_invalidation_reference_windows.json` retains the focused TQP-36 native
edit-invalidation qualification:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_edit_invalidation_validation.gd -- \
  --output res://labs/terrain_lab/results/edit_invalidation_reference_windows.json
```

The report compares every observed generation change against an independent
padded-sample-footprint oracle over all active native application records. It
retains coarse/fine, same-LOD halo, mixed transition, disjoint batch, unloaded
no-op, cancellation, stale supersession, resource coherence, full frame trace,
performance, memory, and provenance evidence. The adjacent motion JSON and
three PNGs are generated by `capture_edit_invalidation_observatory.gd` and are
diagnostic rather than the affected-set authority.

`adaptive_edit_reference_windows.json` retains the focused TQP-37 native
adaptive digging-and-construction qualification:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_adaptive_edit_validation.gd -- \
  --output res://labs/terrain_lab/results/adaptive_edit_reference_windows.json
```

The report retains six isolated LOD1/LOD0 scenarios, authoritative sample
relations, exact selected-interface edge multisets, triangle integrity,
origin/unload/restart/refinement identity, native edit-LOD retention,
reconstructive command-ledger history, temporal ownership, debug performance,
memory, resource, provenance, and sampled frame-trace evidence. The adjacent
motion JSON and three PNGs are generated by
`capture_adaptive_edit_observatory.gd`; they are diagnostic and do not qualify
generic in-place undo, production collision residency, or low-power operation.

`terrain_observatory_diagnostics_reference_windows.json` retains the focused
TQP-26 chunk, job, resource, collision, rejection, event-retention, and signed
repro-export contract:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_terrain_observatory_validation.gd -- \
  --output res://labs/terrain_lab/results/terrain_observatory_diagnostics_reference_windows.json
```

`terrain_qualification_reference_windows.json` is generated by:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_terrain_lab_validation.gd -- \
  --output res://labs/terrain_lab/results/terrain_qualification_reference_windows.json
```

The report qualifies only the scopes declared in the report and program
manifest. Machine-specific timings are evidence for the recorded machine, not
portable performance guarantees. Focused retained runners enforce reviewed
debug regression ceilings. The combined report records post-soak timing
distributions as observation-only so prior-suite load cannot make correctness
qualification flaky.

`large_terrain_soak_reference_windows.json` is generated by the focused native
TQP-27 runner:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_large_terrain_soak_validation.gd -- \
  --output res://labs/terrain_lab/results/large_terrain_soak_reference_windows.json
```

The runner exercises `WorldTransvoxelTerrain` directly over a 128x16x128-chunk
procedural volume. It qualifies only the bounded Windows reference budgets and
durable edit-journal restart declared by `TQP-D016`. Large-volume snapshot
compaction is intentionally exercised as a fail-closed negative control and
remains open as `TQP-F002`; the report is not a production or portable
performance guarantee.

`large_terrain_observatory_validation_windows.json` verifies that the
editor-visible TQP-27 scene uses the same native runtime profile, catalog page
count, backend, viewer radius, and LOD limit as the retained soak. It also
settles center and far-corner teleports and requires clean shutdown:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_large_terrain_observatory_validation.gd -- \
  --output res://labs/terrain_lab/results/large_terrain_observatory_validation_windows.json
```

The corresponding rendered reference is generated by:

```text
godot --rendering-method gl_compatibility --path . --resolution 1440x900 \
  --script labs/terrain_lab/tools/capture_large_terrain_observatory.gd -- \
  --output res://labs/terrain_lab/results/large_terrain_observatory_reference_windows.png
```

The full envelope and bounded center residency comparison is generated with
the same command plus `--mode overview`, writing
`large_terrain_observatory_world_overview_windows.png`.

This evidence qualifies editor-presentation parity only. It does not replace
the TQP-27 performance soak or claim full-world geometry residency.

`surface_shading_review_automation_windows.json` and its six PNG captures are
generated from the dedicated TQP-23 guided review scene by:

```text
godot --path . --resolution 1400x900 \
  --script labs/terrain_lab/tools/capture_surface_shading_review.gd
```

The automation verifies distinct lit, mapped-normal, triplanar-weight,
camera-detail, constant-material shadow-isolation, and shadows-disabled control
presentations at the `0.25 m` native fixture resolution. It does
not replace the required live human review. The scene requires all ten
diagnostics, two full camera cycles, both sun-shadow states, and all eight
observations before it can write a candidate-pass draft; that draft cannot
promote TQP-23 by itself. `TQP-D014` records acceptance of the retained bounded
reference scope.

`surface_shadow_resolution_evidence_windows.json` retains finding `TQP-F001`
with constant-material shadow-on and shadow-off captures at native `0.5 m` and
`0.25 m` sample spacing:

```text
godot --resolution 1280x720 --path . \
  --script labs/terrain_lab/tools/capture_surface_shadow_resolution_evidence.gd
```

This evidence can attribute the stepped cast silhouette to declared mesh
resolution, but it deliberately makes no production visual-quality claim.

## TQP-44 Through TQP-50 CPU Closure

Build and validate the fixed TQP-44 corpus, then use **Project > Tools > Open
TQP-44 Complex Visual Review** for the required human decision:

```text
python labs/terrain_lab/tools/build_complex_visual_temporal_corpus.py
godot --headless --path . --script labs/terrain_lab/tools/run_complex_visual_validation.gd
```

The review verdict can pass only after all 25 stills, all seven motion paths,
and all twelve live source scenes have been traversed in the `@tool` review.
The verdict is invalidated when its retained corpus signature changes.

Run the focused native responsiveness and collision candidates with:

```text
godot --headless --path . --script labs/terrain_lab/tools/run_fast_arrival_validation.gd -- \
  --output res://labs/terrain_lab/results/fast_arrival_responsiveness_reference_windows.json
godot --headless --path . --script labs/terrain_lab/tools/run_targeted_collision_validation.gd -- \
  --output res://labs/terrain_lab/results/targeted_collision_residency_reference_windows.json
```

TQP-47 requires a real Forward+ window and must run without `--headless`:

```text
godot --resolution 1280x720 --path . \
  --script labs/terrain_lab/tools/run_large_world_performance_validation.gd -- \
  --output res://labs/terrain_lab/results/large_world_performance_reference_windows.json
```

TQP-48 uses the inherited GPU-board WPF60 target from the old
`gpu-marching-cubes` benchmark. Preflight fails closed only when
`nvidia-smi power.draw` is unavailable. CPU-package, battery, DC-input, and
AC-input power can be retained as separately labeled observations when trusted
sensors exist, but they do not replace the WPF60 target:

```text
python labs/terrain_lab/tools/measure_low_power_profiles.py
python labs/terrain_lab/tools/measure_low_power_profiles.py --execute
```

The exact run is 300 seconds of warmup plus at least 1800 measured seconds and
108000 measured frames. CLI-shortened runs remain smoke tests and are retained
as `INCOMPLETE_RUN`; they cannot become `MEASURED_TARGET_MISS` or `PASS`.

The exact low-power run is not a smoke test: it performs a 300-second warmup
and 1800-second measurement. A measured miss remains valid baseline evidence.
After focused reports and human/power evidence are current, rebuild the TQP-49
and TQP-50 fail-closed reports with:

```text
python labs/terrain_lab/tools/evaluate_cpu_authority_closure.py
```

`visual_quality_corpus_reference_windows.json`, four fixed PNGs, four H.264
motion videos, and the adversarial shadow controls are generated by:

```text
python labs/terrain_lab/tools/build_visual_quality_corpus.py --godot \
  "C:\\path\\to\\godot.windows.opt.tools.64.exe"
```

This TQP-25 capture requires a real Forward+ render window and must not be run
with `--headless`; the builder also requires `ffmpeg` and `ffprobe` on `PATH`.
Each fixture is rendered twice, requires exact still and motion-frame identity,
retains native geometry and field signatures, and fails on seam, interior-open,
or non-manifold topology evidence. `TQP-D015` records the completed bounded
human acceptance and closes `TQP-F001` only for this reference corpus. Capture
regeneration preserves that formal decision; automation cannot create, broaden,
or replace it.

Validate the retained corpus without regenerating it by:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_visual_quality_validation.gd
```

`investigate_surface_shadows.gd` is a non-retained exploratory sweep for
directional shadow mode, range, split blending, angular softness, and bias. It
writes its images and report under the system temporary directory and is not a
qualification artifact:

```text
godot --resolution 960x540 --path . \
  --script labs/terrain_lab/tools/investigate_surface_shadows.gd
```

`temporal_wave_reference_windows.json` is generated and checked against stable
native invariants by:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_temporal_wave_validation.gd -- \
  --output res://labs/terrain_lab/results/temporal_wave_reference_windows.json
```

Variable frame and job counts are retained as observations. Promotion depends
on the stable samples, hashes, replay, corruption, migration, generation, and
publication invariants in `temporal_wave_standard.json`.

`wave_02_first_batch_reference_windows.json` retains the focused TQP-18,
TQP-19, and TQP-20 exact, systems, performance, and provenance evidence:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_wave_02_validation.gd -- \
  --output res://labs/terrain_lab/results/wave_02_first_batch_reference_windows.json
```

`material_blending_reference.png` is regenerated by
`tools/capture_material_blending_visual.gd`. Its TQP-18 diagnostic scope was
accepted in `TQP-D008`; that decision does not accept production textures,
shaders, or art direction.

`wave_02_second_batch_reference_windows.json` retains the focused TQP-21 and
TQP-22 contract, performance, provenance, and scope evidence:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_wave_02_second_batch_validation.gd -- \
  --output res://labs/terrain_lab/results/wave_02_second_batch_reference_windows.json
```

`phase_03_system_reference_windows.json` retains native TQP-24 Godot render,
collision, field-query, physics-ray, navigation, edit, and generation evidence:

```text
godot --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_phase_03_system_validation.gd -- \
  --output res://labs/terrain_lab/results/phase_03_system_reference_windows.json
```

This fixture requires the real Windows physics and navigation servers; it must
not be generated with `--headless`.

`terrain_observatory_reference.png` is the deterministic Windows
Forward+/D3D12 TQP-21 candidate visual. It uses a 3x3x2 native fixture at
0.5 m per grid unit. Its live audit compares all 33 adjacent same-LOD chunk
pairs and requires the 27 surface-bearing interfaces to match exactly. It also
audits edge multiplicity across the complete assembled window: every interior
edge must occur exactly twice, open edges are permitted only on an exterior
volume plane, and non-manifold edges fail. An injected open-tetrahedron control
proves the topology detector fails on a known three-edge hole. Automated
repeatability does not replace human review. The corrected reference render
was accepted for the narrow TQP-21 texture-system scope in `TQP-D013`.

`terrain_observatory_tangent_seam.png` isolates the canonical crater interface
that exposed the native tangent-edit defect retained by `TQP-D011`. Regenerate
it twice and require byte identity with:

```text
godot --path . --script labs/terrain_lab/tools/capture_terrain_observatory.gd \
  -- --mode seam \
  --output res://labs/terrain_lab/results/terrain_observatory_tangent_seam.png
```

The two-color capture is supporting visual evidence. The authoritative result
is the exact native boundary-edge comparison executed by the scene smoke.

`terrain_observatory_tangent_pole.png` is the close-up regression for the
canonical crater's exact-isovalue lower pole. Before `TQP-D012`, pairwise seams
all passed while the assembled window contained 24 interior open edges. The
retained image, zero-opening assembled audit, negative control, and upstream
M1/M2 regressions jointly support the correction:

```text
godot --path . --script labs/terrain_lab/tools/capture_terrain_observatory.gd \
  -- --mode pole \
  --output res://labs/terrain_lab/results/terrain_observatory_tangent_pole.png
```

`surface_shading_near.png`, `surface_shading_far.png`, and
`surface_shading_evidence_windows.json` retain the separate TQP-23 shader
fixture. The evidence runner creates two cold/warm instances at each fixed
camera and requires all eight measured frames per pass to be byte-identical:

```text
godot --resolution 1280x720 --path . \
  --script labs/terrain_lab/tools/capture_surface_shading_evidence.gd
```

The retained near/far pair is accepted for the bounded TQP-23 reference scope
through `TQP-D014`; it does not alter the accepted TQP-21 observatory shader or
image and does not qualify TQP-25 production visual quality.

The focused CPU shading-contract ceiling is retained separately by:

```text
godot --headless --rendering-method gl_compatibility --path . \
  --script labs/terrain_lab/tools/run_surface_shading_validation.gd -- \
  --output res://labs/terrain_lab/results/surface_shading_contract_reference_windows.json
```

`edit_qualification_reference.png` is the deterministic diagnostic reference
for the seven-brush corpus and six cumulative dig/construction states. It is
generated by:

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/capture_edit_qualification_visual.gd
```

The image is visual-regression evidence, not standalone geometric correctness
or production art acceptance.

`sparse_hierarchy_reference_windows.json` retains the TQP-42 Godot authority
run for the 128x16x128-chunk procedural world. It verifies zero explicit runtime
catalog entries, a 40-byte implicit hierarchy descriptor, central and
finite-boundary edits, sparse compaction, fresh-runtime replay, regenerated
resources, migration, and fail-closed publication and corruption controls.
`sparse_hierarchy_native_benchmark_windows.json` separately retains seven native
runs with p50/p95/p99/worst timings, peak working set, executable SHA-256,
upstream commit, and native contract hash. The `@tool` source and compact/reopen
workflow is retained in
`sparse_hierarchy_observatory_validation_windows.json`.

```text
godot --headless --path . \
  --script labs/terrain_lab/tools/run_sparse_hierarchy_validation.gd -- \
  --output res://labs/terrain_lab/results/sparse_hierarchy_reference_windows.json

godot --headless --path . \
  --script labs/terrain_lab/tools/run_sparse_hierarchy_observatory_validation.gd -- \
  --output res://labs/terrain_lab/results/sparse_hierarchy_observatory_validation_windows.json
```

These reports qualify only the bounded Windows sparse procedural snapshot
profile accepted by `TQP-D031`; production save compatibility remains
unqualified.
