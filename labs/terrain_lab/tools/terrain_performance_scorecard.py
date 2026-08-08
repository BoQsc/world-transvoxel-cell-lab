#!/usr/bin/env python3
"""Build a compact, comparable terrain-performance scorecard."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[3]
DEFAULT_INPUT = (
    ROOT / "labs/terrain_lab/results/low_power_profiles_reference_windows.json"
)
DEFAULT_OUTPUT = (
    ROOT / "labs/terrain_lab/results/terrain_performance_baseline_windows.json"
)


def load_json(path: pathlib.Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def write_json(path: pathlib.Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def number(value: Any, default: float = 0.0) -> float:
    return float(value) if isinstance(value, (int, float)) else default


def integer(value: Any, default: int = 0) -> int:
    return int(value) if isinstance(value, (int, float)) else default


def milliseconds(distribution: dict, key: str) -> float | None:
    value = distribution.get(key)
    return number(value) / 1000.0 if isinstance(value, (int, float)) else None


def per_second(count: int, duration_seconds: float) -> float | None:
    return count / duration_seconds if duration_seconds > 0.0 else None


def focused_latency(report: dict, name: str, percentile_name: str) -> float | None:
    edited = (
        report.get("focused_responsiveness_evidence", {})
        .get("fast_arrival", {})
        .get("edited_latency", {})
    )
    distribution = edited.get(name, {})
    return milliseconds(distribution, percentile_name)


def metric(
    metric_id: str,
    value: float | int | None,
    unit: str,
    preferred_direction: str,
    context: str,
) -> dict:
    return {
        "id": metric_id,
        "value": value,
        "unit": unit,
        "preferred_direction": preferred_direction,
        "context": context,
    }


def build_scorecard(report: dict, source_path: pathlib.Path | None = None) -> dict:
    run_mode = report.get("run_mode", "exact_qualification")
    comparison_only = run_mode != "exact_qualification"
    workload = report.get("workload", {})
    measurement = workload.get("measurement", {})
    frame = measurement.get("frame", {})
    process = measurement.get("process", {})
    physics = measurement.get("physics", {})
    render_cpu = measurement.get("render_cpu", {})
    render_gpu = measurement.get("render_gpu", {})
    deltas = measurement.get("metric_deltas", {})
    actions = measurement.get("action_counts", {})
    memory = measurement.get("memory", {})
    queues = measurement.get("queue_peaks", {})
    duration = number(measurement.get("elapsed_seconds"))
    frames = integer(measurement.get("frame_count"))
    average_frame_ms = duration * 1000.0 / frames if frames > 0 else None
    average_fps = frames / duration if duration > 0.0 else None

    render_publications = integer(deltas.get("application_applied_render"))
    collision_publications = integer(deltas.get("application_applied_collision"))
    published_events = integer(deltas.get("published_events"))
    edit_commits = integer(deltas.get("edit_commits"))

    process_telemetry = report.get("process_telemetry", {})
    if not process_telemetry:
        process_telemetry = {
            "available": False,
            "reason": "source run predates process-wide CPU telemetry",
            "worker_threads_included": False,
        }

    power_observations = report.get("auxiliary_power_observations", {})
    cpu_package = power_observations.get("cpu_package", {})
    if not cpu_package:
        cpu_package = {
            "available": False,
            "boundary": "cpu_package",
            "watts": None,
            "reason": "CPU-package observation absent",
        }

    source = {
        "path": source_path.relative_to(ROOT).as_posix()
        if source_path is not None and source_path.is_relative_to(ROOT)
        else str(source_path) if source_path is not None else None,
        "sha256": sha256(source_path)
        if source_path is not None and source_path.is_file()
        else None,
        "schema": report.get("schema"),
        "status": report.get("status"),
        "run_mode": run_mode,
    }

    comparison_metrics = [
        metric("average_fps", average_fps, "fps", "higher", "whole workload"),
        metric(
            "frame_p95",
            milliseconds(frame, "p95_usec"),
            "ms",
            "lower",
            "whole workload",
        ),
        metric(
            "frame_p99",
            milliseconds(frame, "p99_usec"),
            "ms",
            "lower",
            "whole workload",
        ),
        metric(
            "frame_worst",
            milliseconds(frame, "worst_usec"),
            "ms",
            "lower",
            "whole workload; investigate outliers independently",
        ),
        metric(
            "godot_process_p95",
            milliseconds(process, "p95_usec"),
            "ms",
            "lower",
            "Godot frame process timing; not package energy",
        ),
        metric(
            "process_cpu_core_equivalents",
            process_telemetry.get("average_active_core_equivalents"),
            "logical cores",
            "lower_for_equal_work",
            "process-wide CPU time including worker threads",
        ),
        metric(
            "amortized_process_cpu_ms_per_render_publication",
            process_telemetry.get(
                "amortized_process_cpu_time_per_render_publication_ms"
            ),
            "CPU ms/publication",
            "lower",
            "amortized over the mixed terrain workload",
        ),
        metric(
            "render_publications_per_second",
            per_second(render_publications, duration),
            "publications/s",
            "higher",
            "render publications applied by the terrain runtime",
        ),
        metric(
            "collision_publications_per_second",
            per_second(collision_publications, duration),
            "publications/s",
            "higher",
            "targeted collision publications applied by the terrain runtime",
        ),
        metric(
            "edit_visual_response_p99",
            None
            if comparison_only
            else focused_latency(report, "first_correct_visual", "p99_usec"),
            "ms",
            "lower",
            "focused retained edit evidence",
        ),
        metric(
            "edit_collision_coherence_p99",
            None
            if comparison_only
            else focused_latency(report, "collision_coherence", "p99_usec"),
            "ms",
            "lower",
            "focused retained edit evidence",
        ),
        metric(
            "peak_working_memory",
            integer(memory.get("peak_bytes")),
            "bytes",
            "lower_for_equal_scope",
            "Godot workload monitor",
        ),
        metric(
            "gpu_board_wpf60",
            report.get("gpu_board_wpf60", {}).get("value"),
            "GPU-board WPF60",
            "lower",
            "GPU context only; not CPU or whole-system power",
        ),
        metric(
            "cpu_package_average_power",
            cpu_package.get("watts") if cpu_package.get("available") else None,
            "W",
            "lower_for_equal_work",
            "unavailable until a trusted CPU-package sensor is connected",
        ),
    ]

    limitations = []
    if not process_telemetry.get("available"):
        limitations.append(str(process_telemetry.get("reason", "CPU telemetry unavailable")))
    if not cpu_package.get("available"):
        limitations.append(str(cpu_package.get("reason", "CPU-package power unavailable")))
    if comparison_only:
        limitations.append(
            "Focused visual/collision edit latency is retained context, not remeasured by this development run."
        )
    limitations.extend(
        [
            "GPU-board, CPU-package, and whole-system power are separate boundaries.",
            "Publication rates are comparable only under the same pinned workload and profile.",
            "A development observation cannot qualify or replace retained TQP-48 evidence.",
        ]
    )

    return {
        "schema": "world_transvoxel.terrain_lab.performance_scorecard.v1",
        "source": source,
        "qualification": {
            "retained_complete": bool(report.get("retained_complete")),
            "target_misses": report.get("target_misses", []),
            "comparison_only": comparison_only,
        },
        "environment": {
            "profile_id": report.get("profile_id", workload.get("profile_id")),
            "profile": workload.get("profile", {}),
            "hardware": report.get("hardware", {}),
            "provenance": workload.get("provenance", {}),
            "measurement_seconds": duration,
            "frame_samples": frames,
        },
        "frame_pacing": {
            "average_fps": average_fps,
            "average_frame_ms": average_frame_ms,
            "p50_ms": milliseconds(frame, "p50_usec"),
            "p95_ms": milliseconds(frame, "p95_usec"),
            "p99_ms": milliseconds(frame, "p99_usec"),
            "worst_ms": milliseconds(frame, "worst_usec"),
            "fraction_over_33_333_ms": measurement.get("fraction_over_33_333ms"),
        },
        "cpu": {
            "godot_process_frame_ms": {
                "p50": milliseconds(process, "p50_usec"),
                "p95": milliseconds(process, "p95_usec"),
                "p99": milliseconds(process, "p99_usec"),
                "worst": milliseconds(process, "worst_usec"),
            },
            "physics_frame_ms": {
                "p50": milliseconds(physics, "p50_usec"),
                "p95": milliseconds(physics, "p95_usec"),
                "p99": milliseconds(physics, "p99_usec"),
                "worst": milliseconds(physics, "worst_usec"),
            },
            "render_submission_frame_ms": {
                "p50": milliseconds(render_cpu, "p50_usec"),
                "p95": milliseconds(render_cpu, "p95_usec"),
                "p99": milliseconds(render_cpu, "p99_usec"),
                "worst": milliseconds(render_cpu, "worst_usec"),
            },
            "process_wide": process_telemetry,
            "package_power": cpu_package,
        },
        "terrain_work": {
            "render_publications": render_publications,
            "render_publications_per_second": per_second(render_publications, duration),
            "collision_publications": collision_publications,
            "collision_publications_per_second": per_second(
                collision_publications, duration
            ),
            "published_events": published_events,
            "published_events_per_second": per_second(published_events, duration),
            "edit_commits": edit_commits,
            "dig_commits": integer(actions.get("dig_commits")),
            "construction_commits": integer(actions.get("construction_commits")),
        },
        "responsiveness": {
            "workload_edit_acknowledgement_ms": {
                "p50": milliseconds(
                    measurement.get("edit_acknowledgement", {}), "p50_usec"
                ),
                "p95": milliseconds(
                    measurement.get("edit_acknowledgement", {}), "p95_usec"
                ),
                "p99": milliseconds(
                    measurement.get("edit_acknowledgement", {}), "p99_usec"
                ),
                "worst": milliseconds(
                    measurement.get("edit_acknowledgement", {}), "worst_usec"
                ),
            },
            "edit_acknowledgement_p99_ms": focused_latency(
                report, "input_acknowledgement", "p99_usec"
            )
            if not comparison_only
            else None,
            "edit_visual_response_p99_ms": focused_latency(
                report, "first_correct_visual", "p99_usec"
            )
            if not comparison_only
            else None,
            "edit_collision_coherence_p99_ms": focused_latency(
                report, "collision_coherence", "p99_usec"
            )
            if not comparison_only
            else None,
            "edit_settlement_p95_ms": focused_latency(
                report, "local_settlement", "p95_usec"
            )
            if not comparison_only
            else None,
            "focused_retained_context": {
                "comparison_eligible": not comparison_only,
                "source": report.get("focused_responsiveness_evidence", {})
                .get("fast_arrival", {})
                .get("path"),
                "edit_acknowledgement_p99_ms": focused_latency(
                    report, "input_acknowledgement", "p99_usec"
                ),
                "edit_visual_response_p99_ms": focused_latency(
                    report, "first_correct_visual", "p99_usec"
                ),
                "edit_collision_coherence_p99_ms": focused_latency(
                    report, "collision_coherence", "p99_usec"
                ),
                "edit_settlement_p95_ms": focused_latency(
                    report, "local_settlement", "p95_usec"
                ),
            },
        },
        "resources": {
            "memory": memory,
            "queue_peaks": queues,
        },
        "gpu_context": {
            "render_frame_ms": {
                "p50": milliseconds(render_gpu, "p50_usec"),
                "p95": milliseconds(render_gpu, "p95_usec"),
                "p99": milliseconds(render_gpu, "p99_usec"),
                "worst": milliseconds(render_gpu, "worst_usec"),
            },
            "board_power": report.get("power", {}),
            "board_wpf60": report.get("gpu_board_wpf60", {}),
        },
        "comparison_metrics": comparison_metrics,
        "limitations": limitations,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=pathlib.Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    report = load_json(args.input)
    write_json(args.output, build_scorecard(report, args.input.resolve()))
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
