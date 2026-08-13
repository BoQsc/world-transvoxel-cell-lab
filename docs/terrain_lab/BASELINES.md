# Terrain Lab Baselines

This file records retained baselines that must be understood before changing
performance, authority, or promotion state.

## TQP-48 Through TQP-50 CPU Authority Baseline

Baseline id: `TQP48_GATE_E_CPU_AUTHORITY_2026_08_08`

Commit: `bd848d8 terrain-lab: qualify Gate E CPU authority`

Program revision: `38`

Retained evidence:

- `res://labs/terrain_lab/results/low_power_profiles_reference_windows.json`
- `res://labs/terrain_lab/results/terrain_performance_baseline_windows.json`
- `res://labs/terrain_lab/results/complex_adaptive_soak_recovery_reference_windows.json`
- `res://labs/terrain_lab/results/native_adaptive_terrain_authority_gate_windows.json`
- `res://labs/terrain_lab/results/terrain_qualification_reference_windows.json`
- `res://addons/world_transvoxel_terrain_lab/standards/decisions/TQP-D037.json`

Qualified:

- TQP-48 exact Windows GPU-board WPF60 measurement protocol and retained
  baseline evidence.
- TQP-49 complex adaptive soak and recovery aggregation.
- TQP-50 Gate E native adaptive CPU terrain authority for the bounded Windows
  envelope.

Not qualified:

- Full TQP-48 low-power target pass.
- Whole-system, battery, DC-input, AC-input, or CPU-package power claims.
- Production runtime/API/release claims.
- GPU field generation, GPU meshing, GPU collision readback, or GPU production
  backend claims.

TQP-48 retained result:

| Metric | Target | Retained Result | Status |
|---|---:|---:|---|
| Frame samples | `>= 108000` | `108000` | pass |
| Measured time | `>= 1800 s` | `1802.580076 s` | pass |
| GPU-board WPF60 | `<= 16.0` | `7.138897319856603` | pass |
| Average GPU-board power | observation | `7.128679245283019 W` | retained |
| GPU-board p95 power | observation | `25.43 W` | retained |
| GPU-board worst power | observation | `26.61 W` | retained |
| Frame p50 | observation | `16.374 ms` | retained |
| Frame p95 | `<= 16.666667 ms` | `17.318 ms` | miss |
| Frame p99 | `<= 20.0 ms` | `18.229 ms` | pass |
| Frame worst | `<= 50.0 ms` | `1168.215 ms` | miss |
| Edit visual response p99 | `<= 50.0 ms` | `154.734 ms` | miss |
| Edit collision coherence p99 | `<= 100.0 ms` | `154.734 ms` | miss |

Compact terrain-performance scorecard:

| Metric | Retained Result | Comparison Rule |
|---|---:|---|
| Average frame rate | `59.914 FPS` | higher under the same profile |
| Godot process frame p95 | `19.360 ms` | lower |
| Physics frame p95 | `2.044 ms` | lower |
| Render CPU submission p95 | `1.152 ms` | lower |
| Render publications | `17.947/s` | higher under the same workload |
| Collision publications | `34.712/s` | higher under the same workload |
| Published terrain events | `191.036/s` | higher under the same workload |
| Peak workload memory | `114.53 MiB` | lower for equal scope |
| Peak scheduler/storage queues | `220 / 720` | lower without lost work |
| CPU-package power | not measured | requires a trusted package sensor |

The compact JSON records the source report SHA-256, pinned profile, hardware,
frame distributions, Godot CPU timing, terrain publication throughput, edit
latency, memory, queues, GPU context, power-boundary labels, and limitations.
The exact source run predates process-wide CPU telemetry, so its Godot process
frame timing must not be presented as total CPU-package use.

The TQP-48 report status is `MEASURED_TARGET_MISS`, not `PASS`. It is still
retained complete baseline evidence because the exact protocol completed, all
required workload classes ran, power samples were continuous, and drift passed.

## TQP-55 Through TQP-57 CPU Production Release Baseline

Baseline id: `CPU_TERRAIN_STANDARD_1_0_2026_08_09`

Program revision: `43`

Pins:

- production commit: `2184988ec7d317f6aedc212e6198997b60888dfa`;
- production addon tree: `f727fb2fdd1f06037c7daab239e895fb9a98f359`;
- integration commit: `d3f28a127f9f1d2faba1d8754fd3abf5cf391f0c`;
- native authority commit: `4f1fdb59e3c6200c8f823b99027b2d3f15563858`;
- canonical 94-file addon digest:
  `1b7332ab974b78759df4d1086bd874eca70080e30d5f572867c916f3bb34b25c`;
- deterministic release ZIP digest:
  `84803816f9c6a4b9da99c5300d7743d0b015bba1e318c7039a5c28e6ca38d7fc`.

Retained evidence:

- `res://labs/terrain_lab/results/cpu_production_release_reference_windows.json`
- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_release_matrix_standard.json`
- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_long_haul_standard.json`
- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_release_standard.json`
- `res://addons/world_transvoxel_terrain_lab/standards/decisions/TQP-D041.json`
- `res://addons/world_transvoxel_terrain_lab/standards/decisions/TQP-D042.json`

Production-wrapper long-haul result:

| Metric | Retained Result | Release Rule |
|---|---:|---|
| Duration | `60.350 s` | `>= 60 s` |
| Residency cycles | `80` | `>= 8` |
| Committed edits | `20` | `>= 2` |
| Authoritative queries | `26` | `>= 2` |
| Journal restarts | `6` | `>= 1` |
| Static-memory growth | `1,010,044 bytes` | `<= 67,108,864 bytes` |
| Queue rejections | `0` | `0` |
| Clean shutdown | `true` | required |

This one-minute wrapper test complements rather than replaces the retained
TQP-49 `1802.580076 s` and `108000`-frame native/rendered drift run. The release
is qualified only for Windows x86-64, Godot 4.7, Forward+, the pinned authority,
and the declared reference hardware class. TQP-48's target misses remain part
of the release evidence. GPU terrain, non-Windows systems, arbitrary hardware,
game systems, and universal 16 W at 60 FPS claims are not qualified.

Assembled large-terrain acceptance:

| Metric | Retained Result | Release Rule |
|---|---:|---|
| World extent | `2048x256x2048 cells` | exact |
| Chunk catalog | `128x16x128`, `299520` pages across LODs | exact / `>= 250000` |
| Rendered scenarios | `9 / 9 PASS` | all required |
| Observed live LODs | `LOD0=160`, `LOD1=116`, `LOD2=92` peak counts | all three required |
| Frame p99 envelope | `33.233 ms` | `<= 100 ms` |
| Peak static memory | `70,118,990 bytes` | `<= 1,610,612,736 bytes` |
| Peak scheduler/storage queues | `224 / 467` | `<= 8192 / 8192` |
| Peak render/collision queues | `0 / 3` | `<= 2048 / 256` |
| Live LOD0/L1 seam edges | `2583` | direct audit required |
| Boundary/nonmanifold/orientation/zero-area defects | `0 / 0 / 0 / 0` | all zero |
| Targeted collision | `PASS` | required |
| Dig/construction restart persistence | `PASS` | required |
| Retained captures | `4 / 4 PASS` | all required |

The assembled proof is bounded, not a claim that all 2048x256x2048 cells are
simultaneously resident. It proves a large declared catalog with adaptive
LOD0/LOD1/LOD2 residency around the moving viewer, including a direct mixed-LOD
seam. `TQP-D042` supersedes the exact pins and Gate F basis in `TQP-D041`; the
older decision remains historical evidence rather than current release
authority.

Fresh capture review found no visible geometric split at the audited seam and
no missing or stale edit after far return. The reference material classifier
does produce abrupt white, gray, and yellow regions, and distant silhouettes
retain coarse LOD faceting. Those are retained presentation limitations, not
topology defects. Final texture assets, art direction, and universally smooth
large-terrain material blending remain unqualified.

## CPU-Instrumented Development Baseline

Development baseline id: `TERRAIN_PERFORMANCE_DEV_2026_08_08`

Evidence:

- `res://labs/terrain_lab/results/terrain_performance_dev_windows.json`
- `res://labs/terrain_lab/results/terrain_performance_dev_scorecard_windows.json`

This is a 30-second warmup plus 120-second measurement using the pinned
`low_power_16w_60fps` workload. It covered all ten workload classes and retained
7,200 frames. Its status is `DEV_OBSERVATION_ONLY`; it cannot promote a TQP,
close a gate, or replace the exact TQP-48 evidence.

| Metric | Development Baseline | Comparison Rule |
|---|---:|---|
| Average frame rate | `59.995 FPS` | higher |
| Frame p95 / p99 / worst | `17.711 / 18.282 / 34.675 ms` | lower |
| Godot process frame p95 | `19.601 ms` | lower |
| Process CPU time | `218.844 CPU-s` sampled; `221.117 CPU-s` full-window estimate | lower for equal work |
| Average active logical cores | `1.842` of `4` | lower for equal work |
| Average machine CPU capacity | `46.06%` | lower for equal work |
| Amortized process CPU time per frame | `30.711 CPU-ms` | lower for equal work |
| Amortized process CPU time per render publication | `71.236 CPU-ms` | lower |
| Render publications | `25.864/s` | higher |
| Collision publications | `45.246/s` | higher |
| Process resident memory p50 / worst | `635.25 / 674.25 MiB` | lower |
| Worker threads included | yes | required |
| CPU-package power | not measured | requires a trusted package sensor |

Process CPU time includes Godot worker threads. CPU milliseconds can therefore
exceed wall-clock frame milliseconds when several cores work concurrently.
Publication-normalized values are amortized over the complete mixed terrain
workload; they are valid for before/after comparisons only when the profile,
duration, workload order, hardware, and competing-process conditions match.
Focused visual-response and collision-coherence values are not remeasured by
the short run. The development scorecard leaves those comparison values null
and carries the older focused evidence only as explicitly labelled context.

The short run observed `21.137` GPU-board WPF60 while the GPU warmed from
`63 C` to `71 C`. That value is development context only. It must not be
compared as equivalent to the thermally settled 35-minute TQP-48 result.

CPU-package watts and joules per terrain publication remain intentionally
unavailable. They may be added only from a trusted package-energy sensor and
must remain separate from GPU-board and complete-system power.

Regenerate the compact exact scorecard from the preserved report without
rerunning Godot:

```text
python labs/terrain_lab/tools/terrain_performance_scorecard.py
```

The generated scorecard pins the source report with SHA-256 so a stale or
unexpectedly changed qualification result is visible.

## CPU Finalization Readiness

Readiness id: `CPU_FINALIZATION_PRECONDITION_2026_08_09`

Evidence:

- `res://addons/world_transvoxel_terrain_lab/standards/cpu_finalization_standard.json`
- `res://labs/terrain_lab/results/cpu_finalization_readiness_windows.json`

Status: `PASS`; retained complete; `TQP-58` eligibility is true. This qualifies
CPU-C1 through CPU-C3 and does not convert the target assessment into a pass.
CPU remains the correctness and differential authority.

The retained manifest SHA-256 is
`d916b21044feeced20d523072b0ff232321013bbdbc235411e29e7b2119c6978` and
covers 24 exact reports. Promotable evidence pins:

- `world-transvoxel`: `f0d88fe9f2d844190d11f26cbe9ed9919f7244d1`
- `world-transvoxel-terrain`: `8073b9da8954027d04583fb9b4698c919ff63758`
- Godot: `4.7.1` release runtime, Forward+ Vulkan, Windows x86-64
- CPU boundary: affinity `[0, 1, 2]`, maximum three logical CPUs, builds `-j3`
- selected balanced workers: generation `2`, meshing `2`

The one/two/three-worker sweeps select two workers for both generation and
meshing. Three meshing workers provide no wall-time gain and worsen p99; three
generation workers worsen wall time, memory, and tails. Two measured shortcuts
also regress the pinned comparison and remain excluded.

| Release-runtime profile | Median wall | Median CPU | Active cores | Peak RSS | Max scenario p99 |
|---|---:|---:|---:|---:|---:|
| Low power, 1/1 | `112.831 s` | `159.172 s` | `1.415` | `668.965 MiB` | `30.788 ms` |
| Quality, 3/3 | `93.376 s` | `144.703 s` | `1.550` | `721.902 MiB` | `66.804 ms` |
| Reference, 2/2 | `100.980 s` | `149.188 s` | `1.479` | `700.117 MiB` | `42.194 ms` |
| Balanced full nine, 2/2 | `145.678 s` | `236.672 s` | `1.625` | `726.539 MiB` | `47.442 ms` |

All three balanced repetitions pass LOD0/LOD1/LOD2 topology, seams, edits,
targeted collision, persistence, queues, memory, and clean shutdown. Digging and
construction pass the declared local edit targets: median total latency is
`187.148 ms` and `137.491 ms`. Sustained 60 Hz p99, several first-visual and
settlement targets, and high-speed-flight collision coherence (`105.045 ms`
against `100 ms`) miss. CPU-package and whole-system watts remain unavailable
and must not be inferred from GPU-board power.

The largest retained phase totals are storage loading (`119.217 s`), mesh
worker execution (`69.273 worker-s`), control activity (`62.254 s`), storage
completion (`54.237 s`), and aggregate mesh queue wait (`1339.642 worker-s`).
Render publication (`1.501 s`) and targeted collision apply (`0.585 s`) are not
the dominant costs. These measurements make TQP-58 a valid decision task; they
do not prove that GPU acceleration is automatically the correct answer.

## CPU Production Closure

Evidence:

- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_closure_standard.json`
- `res://labs/terrain_lab/results/cpu_production_closure_windows.json`

Status: `PASS`; all six ordered TQP-R01 through TQP-R06 correction subgates are
retained complete. Evidence pins `world-transvoxel`
`d73fd37211797b043797d072020a48a2eaed7383`, terrain implementation
`81cb3302b134098786aa988d0a69f8c7353ec4cb`, and terrain evidence
`50c8759d18f0880231cbbb88294cad2b90bc4efe` under affinity `[0, 1, 2]` and
build limit `-j3`.

The broad 2048x256x2048-cell acceptance observes LOD0 through LOD3 over 512
global coarse roots with zero overlaps, generation errors, or topology
failures. Its 2,700 samples report maximum scenario p50 `16.308 ms`, maximum
scenario p99 `70.161 ms`, worst single frame `98.044 ms`, and zero frames over
100 ms. The process averages `1.642` occupied cores and peaks at
`1,172,578,304` bytes RSS. Temporal continuity and prefetched-arrival evidence
also pass; collision remains explicitly requested rather than generated for
every visual chunk.

The self-contained `world-transvoxel-terrain` `1.1.0-rc1` clean-install bundle
has digest `8dc0482fe55b3765ed0bdf376141af2cf6d6f07ff78e855942a731b4d4250f57`.
This qualifies a release candidate, not public Godot Asset Library acceptance.
CPU-package and whole-system watts remain unqualified, and no sustained
60 FPS/16 W result is claimed.

## Post-Correction CPU Human Baseline

Readiness id: `CPU_HUMAN_BASELINE_TRACE_PRECONDITION_2026_08_12`

Evidence:

- `res://addons/world_transvoxel_terrain_lab/standards/cpu_human_baseline_trace_standard.json`
- `res://labs/terrain_lab/results/cpu_human_baseline_trace_readiness_windows.json`
- CPU-B1 source report: `world-transvoxel-integration-game` commit `32adc31`,
  `docs/evidence/authoritative_cpu_human_baseline_20260812/baseline.json`
- CPU-B2 source report: evidence commit `0950e3d`, measurement commit
  `5c07dc6`, authority commit `f7a583d`,
  `docs/evidence/cpu_b2_causal_trace_20260813/qualification.json`
- CPU-B3 source report: evidence commit `6bd1e7f`, candidate commit `eb8a69c`,
  authority commit `a8bba83`,
  `docs/evidence/cpu_b3_regional_publication_20260813/qualification.json`
- CPU-B3 human review: commit `bf59a98`, SHA-256
  `81142cdc1ac5f3ffeaccd5fc8e6d2ca6bf5e984433ed2eae3affcfc86f55da93`,
  `docs/evidence/cpu_b3_regional_publication_20260813/human_review.json`
- CPU-B3 exhaustion review: commit `953e51f`, SHA-256
  `c91110aa12c230dc1470b1ae410138ee800ae57e31e51456ce2763e0cebcba49`,
  `docs/evidence/cpu_b3_regional_publication_20260813/exhaustion_review.json`
- CPU-B3A first bounded capture: evidence commit `cb50b7d`, measurement commit
  `ca9ce0f`, result SHA-256
  `349f0ee8a62ef154c9544ba79c367175b7a166e5ed2357001406991a87bb9027`,
  `docs/evidence/cpu_b3a_lod_opening_20260813/result.json`

Status: `IN_PROGRESS`. CPU-B1 and CPU-B2 are `PASS`; CPU-B3 retains a
correctness hotfix candidate but remains `IN_PROGRESS`; TQP-58 is ineligible.
This supersedes only the advancement state;
it does not revoke the older pinned CPU-C or TQP-R evidence.

The three Godot 4.7 editor/debug g23 runs use affinity `[0, 1, 2]`. Median
full-route p99 is `23.162 ms`; maximum full-route frame is `100.428 ms` and
maximum movement-phase frame is `40.329 ms`. One run blocks movement for 30
consecutive frames. Authority commit takes `33.330-66.661 ms`, while exact
render/collision readiness after relocation takes `14532.785 ms`, `316.719 ms`,
and `13206.199 ms`.

CPU-B2 attributes the delayed edit to global visibility staging after all four
edited chunks reach both Godot sinks: last sink `250.569 ms`, replacement ready
`250.586 ms`, visibility batch `13182.573 ms`, and post-sink wait
`12932.004 ms`. The first blocker has 757 replacements and 2,402 retirements.
Observed movement rejection is collision-readiness gating during relocation
backlog, while accepted frame-time spikes remain separate and unresolved.

The route also retains 296 explicitly paired transition-mask starts, successful
finishes, and consumed completions across 24 masks, with no unmatched identity
or invalid mask. The trace is disabled by default. The retained pair observes
26.0% more wall time and 21.0% more process CPU; frame p99 and maximum are lower
in the traced half, so a single pair cannot qualify universal frame overhead.
CPU-B3 performance comparisons must use trace-off runs. CPU-B3 may change only
one proven factor at a time and must rerun complete correctness and human
regression gates before any exhaustion or GPU decision.

The retained CPU-B3 candidate publishes exact cross-LOD edited regions and
batches matching-generation coverage priority. It preserves the production
streaming hashes and records zero mixed ownership or visual/collision divergence.
Its three-run trace-off medians are `3822.632 ms` exact readiness, `25.397 ms`
frame p99, `51.242 ms` maximum frame, 11 blocked frames, and three consecutive
blocked frames. This remains `MEASURED_TARGET_MISS`. The broader viewer-region
experiment was rejected and reverted after median blocked frames rose to 236
and median physics-target wait reached `2885.357 ms`.

Human regression is `ACCEPTED_WITH_KNOWN_LIMITATIONS`: no new rejection-level
correctness failure was observed, but a temporary see-through LOD slice,
residual flight responsiveness problems, and a smaller first-edit delay after
long relocation remain release-blocking. Human review is complete; independent
CPU exhaustion was not established.

The independent review is now complete with decision
`NOT_EXHAUSTED_ADDITIONAL_CPU_ATTRIBUTION_AND_REMEDIATION_REQUIRED`. It does not
revoke the candidate, but it fails CPU-B3 and TQP-58 eligibility because the
temporary LOD opening is unattributed, flight variance is only partially
attributed, regional component-remedy classes remain open, and the evidence
does not prove CPU saturation. CPU-B3A through CPU-B3E are next in order.

The first CPU-B3A route is retained as
`IN_PROGRESS_EVENT_NOT_REPRODUCED`. It sampled 64 dark candidate rays, excluded
all 64 against authored G23 road geometry, and left zero road-clear opening
rays. The complete local native trace contains 72,723 events with zero consumer
gaps or capture/downstream drops. The screenshot is supporting only, and the
83.25 ms mean synchronous observer cost disqualifies the run as a performance
baseline. This attempt neither closes CPU-B3A nor weakens the original human
opening report.

## Run Policy

The exact TQP-48 qualification run is intentionally expensive:

```text
python -B labs/terrain_lab/tools/run_with_cpu_limit.py --logical-cpus 3 -- \
  python -B labs/terrain_lab/tools/measure_low_power_profiles.py --execute
```

It uses a 300-second warmup and 1800-second measurement window. Use it for
promotion, rebaseline, release-candidate evidence, or after changes expected to
affect frame pacing, edit latency, collision latency, power, memory, queues, or
thermal drift.

Shorter development runs are useful, but they must be written to separate files
and must not replace retained qualification evidence. They can guide work, but
they cannot qualify TQP-48, TQP-49, TQP-50, or Gate E, and they cannot replace
the pinned TQP-55 through TQP-57 production release evidence.

The protected development command is:

```text
python -B labs/terrain_lab/tools/run_with_cpu_limit.py --logical-cpus 3 -- \
  python -B labs/terrain_lab/tools/measure_low_power_profiles.py --execute --development-run
```

It defaults to a 30-second warmup and 120-second measurement and writes only to
`terrain_performance_dev_windows.json` and
`terrain_performance_dev_scorecard_windows.json`. The runner rejects any
development attempt to use the retained TQP-48 output path.
