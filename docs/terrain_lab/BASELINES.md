# Terrain Lab Baselines

This file records retained baselines that must be understood before changing
performance, authority, or promotion state.

## TQP-48 Through TQP-50 CPU Authority Baseline

Baseline id: `TQP48_GATE_E_CPU_AUTHORITY_2026_08_08`

Commit: `bd848d8 terrain-lab: qualify Gate E CPU authority`

Program revision: `38`

Retained evidence:

- `res://labs/terrain_lab/results/low_power_profiles_reference_windows.json`
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

The TQP-48 report status is `MEASURED_TARGET_MISS`, not `PASS`. It is still
retained complete baseline evidence because the exact protocol completed, all
required workload classes ran, power samples were continuous, and drift passed.

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
