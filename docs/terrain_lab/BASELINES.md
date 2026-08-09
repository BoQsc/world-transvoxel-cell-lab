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

Program revision: `42`

Pins:

- production commit: `20f0a6e4b5fd32016e106a1bac9c1248f2d2a81f`;
- production addon tree: `bd8b7c6ebde90c483ff354f97db09512008e6fcc`;
- integration commit: `efadb8dd900056e2d7f8696685605281beafb36b`;
- native authority commit: `f4abd7ab4f921f98aba4ee45b4453af0bae53cd8`;
- canonical 87-file addon digest:
  `df63530846029be9b39fe939c18b2cc20c43fbe961aa481428be6ebac174f96b`;
- deterministic release ZIP digest:
  `8df8d0a72096295b33f881d360049d3353325af01d3c3c17197b41109e697e76`.

Retained evidence:

- `res://labs/terrain_lab/results/cpu_production_release_reference_windows.json`
- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_release_matrix_standard.json`
- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_long_haul_standard.json`
- `res://addons/world_transvoxel_terrain_lab/standards/cpu_production_release_standard.json`
- `res://addons/world_transvoxel_terrain_lab/standards/decisions/TQP-D041.json`

Production-wrapper long-haul result:

| Metric | Retained Result | Release Rule |
|---|---:|---|
| Duration | `60.200 s` | `>= 60 s` |
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

## Run Policy

The exact TQP-48 qualification run is intentionally expensive:

```text
python labs/terrain_lab/tools/measure_low_power_profiles.py --execute
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
python labs/terrain_lab/tools/measure_low_power_profiles.py --execute --development-run
```

It defaults to a 30-second warmup and 120-second measurement and writes only to
`terrain_performance_dev_windows.json` and
`terrain_performance_dev_scorecard_windows.json`. The runner rejects any
development attempt to use the retained TQP-48 output path.
