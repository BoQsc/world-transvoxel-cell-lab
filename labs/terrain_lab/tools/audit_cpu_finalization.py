from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[3]
REPOSITORY_ROOT = ROOT.parent
STANDARD_PATH = (
    ROOT
    / "addons"
    / "world_transvoxel_terrain_lab"
    / "standards"
    / "cpu_finalization_standard.json"
)
RESULT_PATH = ROOT / "labs" / "terrain_lab" / "results" / "cpu_finalization_readiness_windows.json"
RELEASE_STANDARD_PATH = (
    ROOT
    / "addons"
    / "world_transvoxel_terrain_lab"
    / "standards"
    / "cpu_production_release_standard.json"
)
DEV_RESULT_PATH = ROOT / "labs" / "terrain_lab" / "results" / "terrain_performance_dev_windows.json"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_show(repository: Path, revision: str, path: str) -> str:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repository.as_posix()}",
            "-C",
            str(repository),
            "show",
            f"{revision}:{path}",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout


def metric_delta(current: dict, previous: dict, key: str) -> int:
    return int(current.get(key, 0)) - int(previous.get(key, 0))


def accepted_scenario_costs(report: dict) -> list[dict]:

    costs = []
    previous = report["initial_snapshot"]["metrics"]
    for scenario in report.get("scenarios", []):
        current = scenario["final_settlement"]["snapshot"]["metrics"]
        mesh_jobs = metric_delta(current, previous, "mesh_jobs")
        mesh_cpu_ms = metric_delta(current, previous, "mesh_job_time_ns_total") / 1_000_000.0
        storage_jobs = metric_delta(current, previous, "storage_completed_requests")
        storage_cpu_ms = metric_delta(current, previous, "storage_load_time_ns_total") / 1_000_000.0
        initial_frames = int(scenario.get("initial_settlement", {}).get("frames", 0))
        final_frames = int(scenario.get("final_settlement", {}).get("frames", 0))
        costs.append(
            {
                "id": scenario.get("id"),
                "kind": scenario.get("kind"),
                "status": scenario.get("status"),
                "settlement_frames": {
                    "initial": initial_frames,
                    "final": final_frames,
                    "combined": initial_frames + final_frames,
                },
                "mesh": {
                    "jobs": mesh_jobs,
                    "cpu_ms_total": round(mesh_cpu_ms, 3),
                    "cpu_ms_per_job": round(mesh_cpu_ms / mesh_jobs, 3) if mesh_jobs else 0.0,
                },
                "storage_generation": {
                    "completed_jobs": storage_jobs,
                    "worker_cpu_ms_total": round(storage_cpu_ms, 3),
                    "worker_cpu_ms_per_job": round(storage_cpu_ms / storage_jobs, 3)
                    if storage_jobs
                    else 0.0,
                },
                "publications": {
                    "render": metric_delta(current, previous, "application_applied_render"),
                    "collision": metric_delta(current, previous, "application_applied_collision"),
                },
                "frame_p95_ms": round(float(scenario["frame"]["p95_usec"]) / 1000.0, 3),
                "render_cpu_p95_ms": round(
                    float(scenario["render_cpu"]["p95_usec"]) / 1000.0, 3
                ),
                "render_gpu_p95_ms": round(
                    float(scenario["render_gpu"]["p95_usec"]) / 1000.0, 3
                ),
                "edit_latency_ms": round(
                    float(scenario.get("edit", {}).get("latency_usec", 0)) / 1000.0,
                    3,
                ),
            }
        )
        previous = current
    return costs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-eligible", action="store_true")
    arguments = parser.parse_args()

    standard = load(STANDARD_PATH)
    release_standard = load(RELEASE_STANDARD_PATH)
    candidate = REPOSITORY_ROOT / "world-transvoxel-terrain"
    authority = REPOSITORY_ROOT / "world-transvoxel"
    large_spec = release_standard["large_terrain_acceptance"]["report"]
    large_report_path = candidate / large_spec["path"]
    large_report = load(large_report_path)
    dev_report = load(DEV_RESULT_PATH)
    failures: list[str] = []

    accepted = standard["accepted_baselines"]
    cpu_release = accepted["cpu_release"]
    dev_baseline = accepted["process_cpu_development_observation"]
    if sha256(large_report_path) != large_spec["sha256"]:
        failures.append("TQP-57 large-terrain report differs from its release pin")
    if large_spec["sha256"] != cpu_release["large_acceptance_report_sha256"]:
        failures.append("CPU-finalization standard large-terrain pin differs from TQP-57")
    if large_report.get("status") != "PASS" or large_report.get("retained_complete") is not True:
        failures.append("TQP-57 large-terrain source report is not a retained PASS")
    if large_report.get("base_revision") != cpu_release["candidate_revision"]:
        failures.append("TQP-57 candidate revision differs from CPU-finalization standard")
    if sha256(DEV_RESULT_PATH) != dev_baseline["sha256"]:
        failures.append("process CPU development observation digest mismatch")
    if dev_report.get("status") != dev_baseline["status"]:
        failures.append("process CPU development observation status mismatch")

    runtime_path = "addons/world_transvoxel/src/services/wt_read_only_world_runtime_publication.cpp"
    lifecycle_path = "addons/world_transvoxel/src/services/wt_world_lifecycle.cpp"
    runtime_source = git_show(authority, cpu_release["native_authority_revision"], runtime_path)
    lifecycle_source = git_show(authority, cpu_release["native_authority_revision"], lifecycle_path)
    serial_mesh = (
        "bool WtReadOnlyWorldRuntime::process_scheduler_jobs()" in runtime_source
        and "page_runtime_->execute_mesh_job(" in runtime_source
        and "for (std::size_t count = 0; count < 4; ++count)" in runtime_source
    )
    one_control_thread = "control_thread_ = std::thread" in lifecycle_source
    if not serial_mesh:
        failures.append("pinned native serial mesh architecture signature was not found")
    if not one_control_thread:
        failures.append("pinned native control-thread architecture signature was not found")

    stages = [
        {
            "id": stage["id"],
            "title": stage["title"],
            "status": stage["status"],
            "depends_on": stage.get("depends_on", []),
            "requirement_count": len(stage["complete_when"]),
        }
        for stage in standard["ordered_closure"]
    ]
    gate_passed = not failures and all(stage["status"] == "qualified" for stage in stages)
    process_telemetry = dev_report.get("process_telemetry", {})
    scenario_costs = accepted_scenario_costs(large_report)
    worst_settlement = max(
        scenario_costs,
        key=lambda item: item["settlement_frames"]["combined"],
    )
    worst_mesh = max(scenario_costs, key=lambda item: item["mesh"]["cpu_ms_total"])
    worst_storage = max(
        scenario_costs,
        key=lambda item: item["storage_generation"]["worker_cpu_ms_total"],
    )

    result = {
        "schema": "world_transvoxel.terrain_lab.cpu_finalization_readiness.v1",
        "date": "2026-08-09",
        "gate_id": standard["gate_id"],
        "status": "PASS" if gate_passed else "BLOCKED" if not failures else "FAIL",
        "retained_complete": gate_passed,
        "tqp58_eligible": gate_passed,
        "standard": {
            "path": STANDARD_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256(STANDARD_PATH),
        },
        "accepted_cpu_release": {
            "candidate_revision": cpu_release["candidate_revision"],
            "native_authority_revision": cpu_release["native_authority_revision"],
            "large_acceptance_report_sha256": sha256(large_report_path),
            "large_acceptance_status": large_report.get("status"),
            "frame_envelope": large_report.get("aggregate", {}).get("frame_envelope", {}),
            "queue_peaks": large_report.get("queue_peaks", {}),
            "memory": large_report.get("memory", {}),
        },
        "accepted_scenario_costs": scenario_costs,
        "cost_findings": {
            "largest_settlement": {
                "scenario": worst_settlement["id"],
                "frames": worst_settlement["settlement_frames"]["combined"],
            },
            "largest_mesh_cpu_total": {
                "scenario": worst_mesh["id"],
                "cpu_ms": worst_mesh["mesh"]["cpu_ms_total"],
            },
            "largest_storage_worker_cpu_total": {
                "scenario": worst_storage["id"],
                "worker_cpu_ms": worst_storage["storage_generation"]["worker_cpu_ms_total"],
            },
            "interpretation": [
                "Ordinary render submission is small compared with streaming settlement work in the accepted run.",
                "Storage and procedural generation use two workers, but mesh execution remains synchronous on one control thread.",
                "Multi-second settlement is explained primarily by page generation and serial meshing throughput, with planner and queue wait not yet fully attributed.",
            ],
        },
        "native_architecture": {
            "authority_revision": cpu_release["native_authority_revision"],
            "control_thread_count": 1 if one_control_thread else None,
            "procedural_generation_worker_count_in_acceptance": 2,
            "mesh_execution": "synchronous_control_thread" if serial_mesh else "unknown",
            "mesh_jobs_per_control_loop_limit": 4 if serial_mesh else None,
            "standard_cpu_parallel_meshing_exhausted": False,
        },
        "process_cpu_context": {
            "status": dev_report.get("status"),
            "comparison_only": True,
            "workload": "120-second low-power mixed development workload; not the TQP-57 large acceptance",
            "logical_cpu_count": process_telemetry.get("logical_cpu_count"),
            "process_cpu_seconds": process_telemetry.get("process_cpu_seconds"),
            "estimated_measurement_cpu_seconds": process_telemetry.get(
                "estimated_measurement_cpu_seconds"
            ),
            "average_active_core_equivalents": process_telemetry.get(
                "average_active_core_equivalents"
            ),
            "average_machine_cpu_capacity_percent": process_telemetry.get(
                "average_machine_cpu_capacity_percent"
            ),
            "cpu_package_power_available": False,
        },
        "excluded_diagnostics": [
            {
                "date": "2026-08-09",
                "count": 2,
                "scope": "isolated TQP-57 windowed process-CPU profiling attempts",
                "disposition": "EXCLUDED_FROM_BASELINE",
                "reason": "each run completed scenarios but failed one different 90-frame nearest-rank p99 gate; the first also used intrusive per-thread sampling",
                "finding": "the profiling protocol and p99 sample design require correction before process telemetry can qualify the assembled baseline",
            }
        ],
        "ordered_closure": stages,
        "open_blockers": standard["current_known_blockers"],
        "promotion_invalidators": standard["invalid_promotion_evidence"],
        "consistency_failures": failures,
        "decision": "TQP-58 remains blocked. CPU correctness is retained, but CPU performance architecture is not finalized and standard CPU improvement paths are not exhausted.",
    }
    RESULT_PATH.write_text(json.dumps(result, indent="\t") + "\n", encoding="utf-8")

    if failures:
        for failure in failures:
            print("WT_TERRAIN_CPU_FINALIZATION_AUDIT_FAIL " + failure)
        return 1
    if arguments.require_eligible and not gate_passed:
        print(
            "WT_TERRAIN_CPU_FINALIZATION_INELIGIBLE "
            f"stages={','.join(stage['id'] for stage in stages if stage['status'] != 'qualified')} "
            "next=TQP-58"
        )
        return 1
    print(
        "WT_TERRAIN_CPU_FINALIZATION_BLOCKED "
        f"stages={','.join(stage['id'] for stage in stages if stage['status'] != 'qualified')} "
        "tqp58_eligible=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
