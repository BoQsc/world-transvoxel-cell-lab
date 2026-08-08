#!/usr/bin/env python3
"""Run the exact TQP-48 GPU-board WPF60 workload when its sensor exists."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import platform
import statistics
import subprocess
import tempfile
import time

try:
    import psutil
except ImportError:  # Optional outside the pinned Windows benchmark host.
    psutil = None

from terrain_performance_scorecard import build_scorecard


ROOT = pathlib.Path(__file__).resolve().parents[3]
RESULTS = ROOT / "labs/terrain_lab/results"
STANDARD = ROOT / "addons/world_transvoxel_terrain_lab/standards/low_power_qualification_standard.json"
OUTPUT = ROOT / "labs/terrain_lab/results/low_power_profiles_reference_windows.json"
DEV_OUTPUT = ROOT / "labs/terrain_lab/results/terrain_performance_dev_windows.json"
SCORECARD_OUTPUT = ROOT / "labs/terrain_lab/results/terrain_performance_baseline_windows.json"
DEV_SCORECARD_OUTPUT = ROOT / "labs/terrain_lab/results/terrain_performance_dev_scorecard_windows.json"
DEFAULT_GODOT = pathlib.Path(r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")
GPU_WPF60_FRAME_MS = 1000.0 / 60.0


def run_text(command: list[str]) -> str:
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=15, check=False).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def battery_status() -> dict:
    command = [
        "powershell.exe", "-NoProfile", "-Command",
        "Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus | Select-Object PowerOnline,Discharging,Charging,DischargeRate,Voltage,RemainingCapacity | ConvertTo-Json -Compress",
    ]
    raw = run_text(command)
    try:
        value = json.loads(raw)
        if isinstance(value, list):
            value = value[0] if value else {}
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        return {}


def gpu_sample() -> dict:
    raw = run_text([
        "nvidia-smi", "--query-gpu=name,driver_version,power.draw,temperature.gpu,utilization.gpu,memory.used",
        "--format=csv,noheader,nounits",
    ])
    if not raw:
        return {}
    values = [part.strip() for part in raw.splitlines()[0].split(",")]
    if len(values) != 6:
        return {}
    try:
        return {"name": values[0], "driver": values[1], "power_w": float(values[2]), "temperature_c": float(values[3]), "utilization_percent": float(values[4]), "memory_mib": float(values[5])}
    except ValueError:
        return {"raw": raw}


def battery_power_observation() -> dict:
    battery = battery_status()
    online = bool(battery.get("PowerOnline", True))
    discharging = bool(battery.get("Discharging", False))
    rate_mw = float(battery.get("DischargeRate", 0) or 0)
    if not online and discharging and rate_mw > 0:
        return {"available": True, "boundary": "complete_system_at_battery", "watts": rate_mw / 1000.0, "source": "Windows root/wmi BatteryStatus.DischargeRate", "battery": battery}
    return {"available": False, "boundary": "complete_system_at_battery", "watts": None, "reason": "battery is not discharging or reports zero discharge", "battery": battery}


def auxiliary_power_observations() -> dict:
    return {
        "complete_system_at_battery": battery_power_observation(),
        "cpu_package": {"available": False, "boundary": "cpu_package", "watts": None, "reason": "trusted RAPL/CPU-package provider not installed"},
        "complete_system_at_ac_input": {"available": False, "boundary": "complete_system_at_ac_input", "watts": None, "reason": "external AC input meter not connected"},
        "complete_system_at_dc_input": {"available": False, "boundary": "complete_system_at_dc_input", "watts": None, "reason": "external DC input meter not connected"},
    }


def accepted_power_sample() -> dict:
    gpu = gpu_sample()
    watts = gpu.get("power_w")
    if isinstance(watts, (int, float)) and float(watts) > 0.0:
        return {
            "available": True,
            "boundary": "gpu_board",
            "watts": float(watts),
            "source": "nvidia-smi power.draw",
            "metric": "gpu_board_wpf60",
            "gpu": gpu,
        }
    return {
        "available": False,
        "boundary": "gpu_board",
        "watts": None,
        "reason": "accepted GPU-board sensor unavailable; nvidia-smi power.draw did not return positive watts",
        "gpu": gpu,
    }


def hardware() -> dict:
    return {"platform": platform.platform(), "machine": platform.machine(), "processor": platform.processor(), "python": platform.python_version(), "gpu": gpu_sample()}


def write_report(report: dict, output: pathlib.Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def load_json(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "MISSING"


def average(values: list[float]) -> float:
    return statistics.fmean(values) if values else 0.0


class ProcessTelemetryMonitor:
    """Sample total Godot process cost, including its worker threads."""

    def __init__(self, process_id: int):
        self.logical_cpu_count = 0
        self.process = None
        self.reason = "psutil is not installed"
        if psutil is None:
            return
        try:
            self.logical_cpu_count = int(psutil.cpu_count(logical=True) or 1)
            self.process = psutil.Process(process_id)
            self.process.cpu_percent(interval=None)
            self.reason = ""
        except (psutil.Error, OSError) as error:
            self.process = None
            self.reason = f"process telemetry initialization failed: {error}"

    def sample(self) -> dict:
        if self.process is None:
            return {
                "available": False,
                "source": "psutil.Process",
                "reason": self.reason,
            }
        try:
            times = self.process.cpu_times()
            cpu_percent = float(self.process.cpu_percent(interval=None))
            memory = self.process.memory_info()
            return {
                "available": True,
                "source": "psutil.Process",
                "provider_version": getattr(psutil, "__version__", None),
                "worker_threads_included": True,
                "logical_cpu_count": self.logical_cpu_count,
                "cpu_user_seconds": float(times.user),
                "cpu_system_seconds": float(times.system),
                "cpu_total_seconds": float(times.user + times.system),
                "cpu_percent_one_core_scale": cpu_percent,
                "machine_cpu_capacity_percent": cpu_percent
                / float(max(1, self.logical_cpu_count)),
                "resident_memory_bytes": int(memory.rss),
                "thread_count": int(self.process.num_threads()),
            }
        except (psutil.Error, OSError) as error:
            return {
                "available": False,
                "source": "psutil.Process",
                "reason": f"process telemetry sample failed: {error}",
            }


def summarize_process_telemetry(
    samples: list[dict],
    measurement_seconds: float,
    frames: int,
    render_publications: int,
    collision_publications: int,
    edit_commits: int,
) -> dict:
    records = [
        sample.get("process", {})
        for sample in samples
        if sample.get("process", {}).get("available")
    ]
    if len(records) < 2:
        reasons = [
            str(sample.get("process", {}).get("reason"))
            for sample in samples
            if sample.get("process", {}).get("reason")
        ]
        return {
            "available": False,
            "source": "psutil.Process",
            "reason": reasons[0] if reasons else "fewer than two CPU telemetry samples",
            "worker_threads_included": False,
        }

    first_sample = next(
        sample for sample in samples if sample.get("process", {}).get("available")
    )
    last_sample = next(
        sample
        for sample in reversed(samples)
        if sample.get("process", {}).get("available")
    )
    first = first_sample["process"]
    last = last_sample["process"]
    sampled_seconds = max(
        0.0,
        float(last_sample.get("timestamp_unix_seconds", 0.0))
        - float(first_sample.get("timestamp_unix_seconds", 0.0)),
    )
    cpu_seconds = max(
        0.0,
        float(last.get("cpu_total_seconds", 0.0))
        - float(first.get("cpu_total_seconds", 0.0)),
    )
    logical_cpu_count = int(last.get("logical_cpu_count", 1) or 1)
    active_core_equivalents = (
        cpu_seconds / sampled_seconds if sampled_seconds > 0.0 else None
    )
    sample_coverage_fraction = (
        min(1.0, sampled_seconds / measurement_seconds)
        if measurement_seconds > 0.0
        else 0.0
    )
    estimated_measurement_cpu_seconds = (
        cpu_seconds / sample_coverage_fraction
        if sample_coverage_fraction > 0.0
        else None
    )
    cpu_percentages = [
        float(record.get("cpu_percent_one_core_scale", 0.0)) for record in records[1:]
    ]
    resident_memory = [
        float(record.get("resident_memory_bytes", 0.0)) for record in records
    ]
    thread_counts = [float(record.get("thread_count", 0.0)) for record in records]

    def cpu_time_per(count: int) -> float | None:
        return (
            estimated_measurement_cpu_seconds * 1000.0 / float(count)
            if count > 0 and estimated_measurement_cpu_seconds is not None
            else None
        )

    return {
        "available": True,
        "source": "psutil.Process cpu_times/cpu_percent/memory_info",
        "provider_version": getattr(psutil, "__version__", None),
        "worker_threads_included": True,
        "sample_count": len(records),
        "sampled_seconds": sampled_seconds,
        "measurement_seconds": measurement_seconds,
        "sample_coverage_fraction": sample_coverage_fraction,
        "logical_cpu_count": logical_cpu_count,
        "process_cpu_seconds": cpu_seconds,
        "estimated_measurement_cpu_seconds": estimated_measurement_cpu_seconds,
        "average_active_core_equivalents": active_core_equivalents,
        "average_machine_cpu_capacity_percent": active_core_equivalents
        / float(logical_cpu_count)
        * 100.0
        if active_core_equivalents is not None
        else None,
        "sampled_cpu_percent_one_core_scale": {
            "p50": percentile(cpu_percentages, 0.50),
            "p95": percentile(cpu_percentages, 0.95),
            "worst": max(cpu_percentages, default=0.0),
        },
        "amortized_process_cpu_time_per_frame_ms": cpu_time_per(frames),
        "amortized_process_cpu_time_per_render_publication_ms": cpu_time_per(
            render_publications
        ),
        "amortized_process_cpu_time_per_collision_publication_ms": cpu_time_per(
            collision_publications
        ),
        "amortized_process_cpu_time_per_edit_commit_ms": cpu_time_per(edit_commits),
        "resident_memory_bytes": {
            "p50": percentile(resident_memory, 0.50),
            "p95": percentile(resident_memory, 0.95),
            "worst": max(resident_memory, default=0.0),
        },
        "thread_count": {
            "p50": percentile(thread_counts, 0.50),
            "p95": percentile(thread_counts, 0.95),
            "worst": max(thread_counts, default=0.0),
        },
    }


def average_frame_ms(measurement: dict) -> float:
    frames = int(measurement.get("frame_count", 0) or 0)
    duration = float(measurement.get("elapsed_seconds", 0.0) or 0.0)
    return (duration * 1000.0 / float(frames)) if frames > 0 and duration > 0.0 else 0.0


def gpu_board_wpf60(power_w: float, frame_ms: float) -> float:
    if power_w <= 0.0 or frame_ms <= 0.0:
        return 0.0
    return power_w * frame_ms / GPU_WPF60_FRAME_MS


def drift_qualification(
    standard: dict,
    workload: dict,
    power_samples: list[dict],
    protocol_complete: bool,
) -> dict:
    acceptance = load_json(
        ROOT
        / "addons/world_transvoxel_terrain_lab/standards/"
        "complex_adaptive_soak_recovery_standard.json"
    ).get("acceptance", {})
    windows = workload.get("measurement", {}).get("drift_windows", [])
    band_size = max(1, len(windows) // 5)
    first = windows[:band_size]
    last = windows[-band_size:] if windows else []

    def band_average(records: list[dict], value) -> float:
        return average([float(value(record)) for record in records])

    first_memory = band_average(first, lambda item: item.get("memory_bytes", 0))
    last_memory = band_average(last, lambda item: item.get("memory_bytes", 0))
    memory_growth = max(0.0, last_memory - first_memory)
    memory_limit = (
        first_memory * float(acceptance.get("maximum_memory_growth_fraction", 0.0))
        + float(acceptance.get("maximum_memory_growth_allowance_bytes", 0.0))
    )
    first_frame = band_average(
        first, lambda item: item.get("frame", {}).get("p99_usec", 0.0)
    )
    last_frame = band_average(
        last, lambda item: item.get("frame", {}).get("p99_usec", 0.0)
    )
    frame_growth = max(0.0, last_frame - first_frame)
    frame_limit = (
        first_frame * float(acceptance.get("maximum_frame_p99_drift_fraction", 0.0))
        + float(acceptance.get("maximum_frame_p99_drift_allowance_usec", 0.0))
    )

    def queue_depth(item: dict) -> int:
        return sum(int(value) for value in item.get("queue_peaks", {}).values())

    first_queue = band_average(first, queue_depth)
    last_queue = band_average(last, queue_depth)
    queue_growth = max(0.0, last_queue - first_queue)
    queue_limit = (
        first_queue
        * float(acceptance.get("maximum_queue_depth_drift_fraction", 0.0))
        + float(acceptance.get("maximum_queue_depth_drift_allowance", 0.0))
    )
    watts = [
        float(sample.get("primary_power", sample.get("system", {})).get("watts", 0.0))
        for sample in power_samples
        if sample.get("primary_power", sample.get("system", {})).get("available")
    ]
    power_band = max(1, len(watts) // 4)
    first_power = average(watts[:power_band])
    last_power = average(watts[-power_band:])
    power_growth = max(0.0, last_power - first_power)
    power_limit = (
        first_power * float(acceptance.get("maximum_power_drift_fraction", 0.0))
        + float(acceptance.get("maximum_power_drift_allowance_watts", 0.0))
    )
    temperatures = [
        float(sample.get("gpu", {}).get("temperature_c"))
        for sample in power_samples
        if sample.get("gpu", {}).get("temperature_c") is not None
    ]
    temperature_start = temperatures[0] if temperatures else 0.0
    temperature_end = temperatures[-1] if temperatures else 0.0
    temperature_max = max(temperatures, default=0.0)
    checks = {
        "protocol_complete": protocol_complete,
        "minimum_drift_windows": len(windows) >= 2,
        "memory_growth_bounded": memory_growth <= memory_limit,
        "frame_p99_growth_bounded": frame_growth <= frame_limit,
        "queue_growth_bounded": queue_growth <= queue_limit,
        "power_growth_bounded": bool(watts) and power_growth <= power_limit,
        "temperature_recorded": bool(temperatures),
        "temperature_bounded": bool(temperatures)
        and temperature_max
        <= float(acceptance.get("maximum_gpu_temperature_c", 0.0)),
        "temperature_drift_bounded": bool(temperatures)
        and temperature_end - temperature_start
        <= float(acceptance.get("maximum_gpu_temperature_drift_c", 0.0)),
    }
    return {
        "status": "PASS" if all(checks.values()) else "FAIL",
        "checks": checks,
        "window_count": len(windows),
        "memory": {
            "first_band_average_bytes": first_memory,
            "last_band_average_bytes": last_memory,
            "growth_bytes": memory_growth,
            "maximum_growth_bytes": memory_limit,
        },
        "frame_p99": {
            "first_band_average_usec": first_frame,
            "last_band_average_usec": last_frame,
            "growth_usec": frame_growth,
            "maximum_growth_usec": frame_limit,
        },
        "queues": {
            "first_band_average_depth": first_queue,
            "last_band_average_depth": last_queue,
            "growth": queue_growth,
            "maximum_growth": queue_limit,
        },
        "power": {
            "first_quarter_average_w": first_power,
            "last_quarter_average_w": last_power,
            "growth_w": power_growth,
            "maximum_growth_w": power_limit,
        },
        "thermal": {
            "start_c": temperature_start if temperatures else None,
            "end_c": temperature_end if temperatures else None,
            "maximum_c": temperature_max if temperatures else None,
        },
    }


def preflight(standard: dict, output: pathlib.Path) -> int:
    power = accepted_power_sample()
    report = {
        "schema": "world_transvoxel.terrain_lab.low_power_profiles_qualification.v2",
        "milestone": "TQP-48",
        "standard_id": standard["standard_id"],
        "status": "READY_FOR_EXACT_RUN" if power["available"] else "BLOCKED_ACCEPTED_POWER_SENSOR_UNAVAILABLE",
        "retained_complete": False,
        "primary_metric": "gpu_board_wpf60",
        "profiles_frozen": standard["profiles"],
        "measurement_contract": standard["measurement"],
        "hardware": hardware(),
        "power_preflight": power,
        "auxiliary_power_observations": auxiliary_power_observations(),
        "qualified_scope": [],
        "explicitly_unqualified_scope": standard["explicitly_unqualified_scope"],
        "blockers": [] if power["available"] else [power["reason"]],
    }
    write_report(report, output)
    return 0 if power["available"] else 2


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    return ordered[min(len(ordered) - 1, int((len(ordered) - 1) * fraction))]


def execute(standard: dict, args: argparse.Namespace) -> int:
    initial = accepted_power_sample()
    if not initial["available"]:
        return preflight(standard, args.output)
    workload_path = pathlib.Path(tempfile.gettempdir()) / "tqp48_low_power_workload.json"
    command = [
        str(args.godot), "--path", str(ROOT), "--script", "res://labs/terrain_lab/tools/run_low_power_profile_workload.gd", "--",
        "--profile", args.profile, "--warmup-seconds", str(args.warmup_seconds),
        "--measurement-seconds", str(args.measurement_seconds), "--output", str(workload_path),
    ]
    process = subprocess.Popen(command, cwd=ROOT)
    process_monitor = ProcessTelemetryMonitor(process.pid)
    samples: list[dict] = []
    monitor_started = time.monotonic()
    next_sample = monitor_started
    while process.poll() is None:
        power = accepted_power_sample()
        gpu = power.get("gpu") if isinstance(power.get("gpu"), dict) else gpu_sample()
        samples.append(
            {
                "elapsed_s": time.monotonic() - monitor_started,
                "timestamp_unix_seconds": time.time(),
                "primary_power": power,
                "gpu": gpu,
                "auxiliary_power": auxiliary_power_observations(),
                "process": process_monitor.sample(),
            }
        )
        next_sample += args.sample_interval
        time.sleep(max(0.0, next_sample - time.monotonic()))
    if not workload_path.exists():
        workload = {"status": "FAIL", "failures": ["Godot workload report absent"]}
    else:
        workload = json.loads(workload_path.read_text(encoding="utf-8"))
    contract = standard["measurement"]
    measurement = workload.get("measurement", {})
    warmup = workload.get("warmup", {})
    frames = int(measurement.get("frame_count", 0))
    duration = float(measurement.get("elapsed_seconds", 0.0))
    wall_clock = workload.get("measurement_wall_clock", {})
    measurement_started = float(wall_clock.get("started_unix_seconds", 0.0))
    measurement_ended = float(wall_clock.get("ended_unix_seconds", 0.0))
    measurement_samples = [
        sample
        for sample in samples
        if measurement_started
        <= float(sample.get("timestamp_unix_seconds", 0.0))
        <= measurement_ended
    ]
    watts = [
        float(sample["primary_power"]["watts"])
        for sample in measurement_samples
        if sample["primary_power"].get("available")
    ]
    average_watts = average(watts)
    avg_frame_ms = average_frame_ms(measurement)
    measured_wpf60 = gpu_board_wpf60(average_watts, avg_frame_ms)
    energy_j = average_watts * duration
    published = int(
        measurement.get("metric_deltas", {}).get("application_applied_render", 0)
    )
    collision_publications = int(
        measurement.get("metric_deltas", {}).get("application_applied_collision", 0)
    )
    edit_commits = int(
        measurement.get("metric_deltas", {}).get("edit_commits", 0)
    )
    process_telemetry = summarize_process_telemetry(
        measurement_samples,
        duration,
        frames,
        published,
        collision_publications,
        edit_commits,
    )
    target = json.loads((ROOT / "addons/world_transvoxel_terrain_lab/standards/low_power_performance_profile.json").read_text(encoding="utf-8"))
    pacing = target["frame_pacing_targets"]
    responsiveness = target["responsiveness_targets"]
    frame = measurement.get("frame", {})
    action_counts = measurement.get("action_counts", {})
    workload_counts = measurement.get("workload_counts", {})
    fast_path = RESULTS / "fast_arrival_responsiveness_reference_windows.json"
    collision_path = RESULTS / "targeted_collision_residency_reference_windows.json"
    fast = load_json(fast_path)
    collision = load_json(collision_path)
    edited = fast.get("distributions", {}).get("edited", {})
    focused_evidence = {
        "fast_arrival": {
            "path": fast_path.relative_to(ROOT).as_posix(),
            "sha256": sha256(fast_path),
            "status": fast.get("status", "MISSING"),
            "retained_complete": bool(fast.get("retained_complete")),
            "edited_latency": edited,
        },
        "targeted_collision": {
            "path": collision_path.relative_to(ROOT).as_posix(),
            "sha256": sha256(collision_path),
            "status": collision.get("status", "MISSING"),
            "retained_complete": bool(collision.get("retained_complete")),
            "collision_arrival": collision.get("collision_arrival_distribution", {}),
            "edit_replacement": collision.get("edit_replacement", {}),
        },
    }
    expected_power_samples = int(duration / max(args.sample_interval, 0.001) * 0.90)
    required_classes = contract["required_workload_classes"]
    protocol_checks = {
        "runner_success": process.returncode == 0 and workload.get("status") == "PASS",
        "exact_profile": args.profile == "low_power_16w_60fps"
        and workload.get("profile_id") == args.profile
        and workload.get("profile") == standard["profiles"][args.profile],
        "exact_warmup": args.warmup_seconds == int(contract["warmup_seconds"])
        and int(warmup.get("requested_seconds", -1)) == int(contract["warmup_seconds"])
        and float(warmup.get("elapsed_seconds", 0.0)) >= float(contract["warmup_seconds"]),
        "exact_measurement": args.measurement_seconds
        == int(contract["steady_state_seconds"])
        and int(measurement.get("requested_seconds", -1))
        == int(contract["steady_state_seconds"])
        and duration >= float(contract["steady_state_seconds"]),
        "minimum_frame_samples": frames >= int(contract["minimum_frame_samples"]),
        "workload_class_coverage": all(
            int(workload_counts.get(name, 0)) > 0 for name in required_classes
        ),
        "dig_and_construction_executed": int(action_counts.get("dig_commits", 0)) > 0
        and int(action_counts.get("construction_commits", 0)) > 0
        and int(action_counts.get("edit_rejections", 0)) == 0,
        "multiple_collision_invokers_executed": int(
            action_counts.get("secondary_invoker_updates", 0)
        )
        > 0
        and int(action_counts.get("secondary_invoker_rejections", 0)) == 0,
        "resource_retirement_executed": int(
            action_counts.get("secondary_invoker_retirements", 0)
        )
        > 0
        and int(action_counts.get("retirement_rejections", 0)) == 0,
        "accepted_power_boundary_continuous": bool(samples)
        and all(sample.get("primary_power", {}).get("available") for sample in samples)
        and all(
            sample.get("primary_power", {}).get("boundary") == initial["boundary"]
            for sample in samples
        ),
        "power_sample_coverage": len(measurement_samples) >= expected_power_samples
        and len(watts) == len(measurement_samples),
        "focused_responsiveness_evidence": fast.get("status") == "PASS"
        and bool(fast.get("retained_complete"))
        and collision.get("status") == "PASS"
        and bool(collision.get("retained_complete")),
        "measurement_power_window_pinned": measurement_started > 0.0
        and measurement_ended > measurement_started,
        "drift_windows_recorded": len(measurement.get("drift_windows", [])) >= 2,
    }
    retained_complete = not args.development_run and all(protocol_checks.values())
    development_checks = {
        "runner_success": process.returncode == 0 and workload.get("status") == "PASS",
        "profile_pinned": workload.get("profile_id") == args.profile
        and workload.get("profile") == standard["profiles"][args.profile],
        "measurement_completed": frames > 0
        and duration >= float(args.measurement_seconds),
        "workload_class_coverage": all(
            int(workload_counts.get(name, 0)) > 0 for name in required_classes
        ),
        "dig_and_construction_executed": int(action_counts.get("dig_commits", 0)) > 0
        and int(action_counts.get("construction_commits", 0)) > 0
        and int(action_counts.get("edit_rejections", 0)) == 0,
        "multiple_collision_invokers_executed": int(
            action_counts.get("secondary_invoker_updates", 0)
        )
        > 0
        and int(action_counts.get("secondary_invoker_rejections", 0)) == 0,
        "resource_retirement_executed": int(
            action_counts.get("secondary_invoker_retirements", 0)
        )
        > 0
        and int(action_counts.get("retirement_rejections", 0)) == 0,
        "accepted_power_boundary_continuous": bool(samples)
        and all(sample.get("primary_power", {}).get("available") for sample in samples),
        "power_sample_coverage": len(measurement_samples) >= expected_power_samples
        and len(watts) == len(measurement_samples),
        "process_wide_cpu_telemetry": bool(process_telemetry.get("available"))
        and float(process_telemetry.get("sample_coverage_fraction", 0.0)) >= 0.90,
    }
    development_complete = args.development_run and all(development_checks.values())
    target_checks = {
        "frame_p95": float(frame.get("p95_usec", 1e30))
        <= float(pacing["maximum_p95_frame_ms"]) * 1000.0,
        "frame_p99": float(frame.get("p99_usec", 1e30))
        <= float(pacing["maximum_p99_frame_ms"]) * 1000.0,
        "frame_worst": float(frame.get("worst_usec", 1e30))
        <= float(pacing["maximum_worst_frame_ms"]) * 1000.0,
        "frame_stutter_fraction": float(
            measurement.get("fraction_over_33_333ms", 1.0)
        )
        <= float(pacing["maximum_fraction_over_33_333_ms"]),
        "gpu_board_wpf60": measured_wpf60 <= float(contract["target_wpf60"]),
        "edit_acknowledgement": float(
            edited.get("input_acknowledgement", {}).get("p99_usec", 1e30)
        )
        <= float(responsiveness["maximum_input_to_edit_acknowledgement_ms"])
        * 1000.0,
        "edit_visual_response": float(
            edited.get("first_correct_visual", {}).get("p99_usec", 1e30)
        )
        <= float(responsiveness["maximum_edit_to_first_visible_response_ms"])
        * 1000.0,
        "edit_collision_coherence": float(
            edited.get("collision_coherence", {}).get("p99_usec", 1e30)
        )
        <= float(responsiveness["maximum_edit_to_local_collision_coherence_ms"])
        * 1000.0,
        "edit_settlement": float(
            edited.get("local_settlement", {}).get("p95_usec", 1e30)
        )
        <= float(responsiveness["maximum_background_edit_settlement_p95_ms"])
        * 1000.0,
    }
    pass_target = retained_complete and all(target_checks.values())
    drift = drift_qualification(
        standard,
        workload,
        measurement_samples,
        retained_complete or development_complete,
    )
    status = (
        "DEV_OBSERVATION_ONLY"
        if development_complete
        else "DEV_RUN_FAILED"
        if args.development_run
        else "PASS"
        if pass_target
        else "MEASURED_TARGET_MISS"
        if retained_complete
        else "INCOMPLETE_RUN"
    )
    report = {
        "schema": "world_transvoxel.terrain_lab.low_power_profiles_qualification.v2",
        "milestone": "TQP-48", "standard_id": standard["standard_id"],
        "status": status,
        "run_mode": "development_observation"
        if args.development_run
        else "exact_qualification",
        "retained_complete": retained_complete,
        "primary_metric": "gpu_board_wpf60",
        "profile_id": args.profile, "profiles_frozen": standard["profiles"],
        "measurement_contract": standard["measurement"], "hardware": hardware(),
        "power_boundary": initial["boundary"], "power_source": initial["source"],
        "power": {
            "boundary": initial["boundary"],
            "source": initial["source"],
            "samples": len(watts),
            "average_w": average_watts,
            "p95_w": percentile(watts, 0.95),
            "worst_w": max(watts, default=0.0),
            "energy_j": energy_j,
            "energy_per_frame_j": energy_j / frames if frames else None,
            "energy_per_published_chunk_j": energy_j / published if published else None,
        },
        "gpu_board_wpf60": {
            "formula": "gpu_board_average_watts * average_frame_ms / 16.666667",
            "average_frame_ms": avg_frame_ms,
            "average_gpu_board_watts": average_watts,
            "value": measured_wpf60,
            "target": float(contract["target_wpf60"]),
            "over_target": max(0.0, measured_wpf60 - float(contract["target_wpf60"])),
        },
        "auxiliary_power_observations": auxiliary_power_observations(),
        "process_telemetry": process_telemetry,
        "thermal": {"gpu_start_c": samples[0].get("gpu", {}).get("temperature_c") if samples else None, "gpu_end_c": samples[-1].get("gpu", {}).get("temperature_c") if samples else None},
        "workload": workload, "raw_power_samples": samples,
        "measurement_power_samples": measurement_samples,
        "focused_responsiveness_evidence": focused_evidence,
        "protocol_checks": protocol_checks,
        "development_checks": development_checks,
        "development_target_observations": target_checks
        if args.development_run
        else {},
        "target_checks": target_checks,
        "drift_qualification": drift,
        "qualified_scope": standard["qualified_scope"] if retained_complete else [],
        "explicitly_unqualified_scope": standard["explicitly_unqualified_scope"],
        "blockers": [
            name
            for name, passed in (
                development_checks.items()
                if args.development_run
                else protocol_checks.items()
            )
            if not passed
        ],
        "target_misses": []
        if args.development_run
        else [name for name, passed in target_checks.items() if not passed],
        "target_miss_is_baseline_evidence": retained_complete and not pass_target,
    }
    write_report(report, args.output)
    write_report(build_scorecard(report, args.output.resolve()), args.scorecard_output)
    if args.development_run:
        return 0 if development_complete else 2
    return 0 if pass_target else 1 if retained_complete else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--development-run", action="store_true")
    parser.add_argument("--profile", default="low_power_16w_60fps")
    parser.add_argument("--warmup-seconds", type=int)
    parser.add_argument("--measurement-seconds", type=int)
    parser.add_argument("--sample-interval", type=float, default=2.0)
    parser.add_argument("--godot", type=pathlib.Path, default=DEFAULT_GODOT)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--scorecard-output", type=pathlib.Path)
    args = parser.parse_args()
    if args.development_run:
        if not args.execute:
            parser.error("--development-run requires --execute")
        args.warmup_seconds = args.warmup_seconds or 30
        args.measurement_seconds = args.measurement_seconds or 120
        args.output = args.output or DEV_OUTPUT
        args.scorecard_output = args.scorecard_output or DEV_SCORECARD_OUTPUT
        if args.output.resolve() == OUTPUT.resolve():
            parser.error("a development run cannot overwrite retained TQP-48 evidence")
        if args.scorecard_output.resolve() == SCORECARD_OUTPUT.resolve():
            parser.error("a development run cannot overwrite the exact scorecard")
    else:
        args.warmup_seconds = args.warmup_seconds or 300
        args.measurement_seconds = args.measurement_seconds or 1800
        args.output = args.output or OUTPUT
        args.scorecard_output = args.scorecard_output or SCORECARD_OUTPUT
    if args.warmup_seconds <= 0 or args.measurement_seconds <= 0:
        parser.error("warmup and measurement durations must be positive")
    if args.sample_interval <= 0.0:
        parser.error("sample interval must be positive")
    standard = json.loads(STANDARD.read_text(encoding="utf-8"))
    return execute(standard, args) if args.execute else preflight(standard, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
