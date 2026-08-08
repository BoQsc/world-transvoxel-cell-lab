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
they cannot qualify TQP-48, TQP-49, TQP-50, or Gate E.

The protected development command is:

```text
python labs/terrain_lab/tools/measure_low_power_profiles.py --execute --development-run
```

It defaults to a 30-second warmup and 120-second measurement and writes only to
`terrain_performance_dev_windows.json` and
`terrain_performance_dev_scorecard_windows.json`. The runner rejects any
development attempt to use the retained TQP-48 output path.
