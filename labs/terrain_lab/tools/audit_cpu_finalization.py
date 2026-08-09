from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import statistics
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
EVIDENCE_ROOT = ROOT / "labs" / "terrain_lab" / "results" / "cpu_finalization"
RESULT_PATH = (
    ROOT
    / "labs"
    / "terrain_lab"
    / "results"
    / "cpu_finalization_readiness_windows.json"
)

FULL_SCENARIOS = [
    "idle_steady",
    "ground_traversal",
    "high_speed_flight",
    "vertical_cave",
    "adaptive_lod_churn",
    "cold_teleport",
    "digging",
    "construction",
    "far_return",
]
FOCUSED_SCENARIOS = [
    "ground_traversal",
    "cold_teleport",
    "digging",
    "construction",
    "far_return",
]
C1_REPORTS = {
    "debug_editor": "cpu3-c1-debug-balanced-r1.json",
    "release_native_editor_host": "cpu3-c1-release-native-host-balanced-r1.json",
}
MESH_SWEEP = {
    1: "cpu3-c2-release-w1-r1.json",
    2: "cpu3-c2-release-w2-r1.json",
    3: "cpu3-c2-release-w3-r1.json",
}
GENERATION_SWEEP = {
    1: "cpu3-c2-generation-g1-m2.json",
    2: "cpu3-c2-release-w2-r1.json",
    3: "cpu3-c2-generation-g3-m2.json",
}
PROFILE_REPORTS = {
    "low_power": [
        "cpu3-c3-profile-low-power-r1.json",
        "cpu3-c3-profile-low-power-r2.json",
        "cpu3-c3-profile-low-power-r3.json",
    ],
    "quality": [
        "cpu3-c3-profile-quality-r1.json",
        "cpu3-c3-profile-quality-r2.json",
        "cpu3-c3-profile-quality-r3.json",
    ],
    "reference": [
        "cpu3-c3-profile-reference-r1.json",
        "cpu3-c3-profile-reference-r2.json",
        "cpu3-c3-profile-reference-r3.json",
    ],
    "balanced": [
        "cpu3-c3-final-balanced-r1.json",
        "cpu3-c3-final-balanced-r2.json",
        "cpu3-c3-final-balanced-r3.json",
    ],
}
PROFILE_WORKERS = {
    "low_power": (1, 1),
    "balanced": (2, 2),
    "quality": (3, 3),
    "reference": (2, 2),
}
PHASES = [
    "control_active",
    "storage_completion",
    "storage_load",
    "mesh_prepare",
    "mesh_worker_execute",
    "mesh_worker_queue_wait_ns_total",
    "viewer_planning",
    "scheduler_dispatch",
    "render_publication",
    "collision_apply",
    "main_process",
    "retirement",
]


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def median(values) -> float:
    return float(statistics.median(values))


def git_show(repository: Path, revision: str, relative_path: str) -> str:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repository.as_posix()}",
            "-C",
            str(repository),
            "show",
            f"{revision}:{relative_path}",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout


def expect(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def run_summary(report: dict) -> dict:
    process = report["process_telemetry"]["whole_run"]
    return {
        "wall_seconds": round(float(process["wall_seconds"]), 6),
        "process_cpu_seconds": round(float(process["process_cpu_seconds"]), 6),
        "average_active_core_equivalents": round(
            float(process["average_active_core_equivalents"]), 6
        ),
        "peak_boundary_rss_mib": round(
            int(process["rss_bytes_maximum_boundary_sample"]) / 1_048_576.0,
            3,
        ),
        "maximum_scenario_frame_p99_ms": round(
            max(float(item["frame"]["p99_usec"]) for item in report["scenarios"])
            / 1000.0,
            3,
        ),
        "maximum_scenario_frame_worst_ms": round(
            max(float(item["frame"]["worst_usec"]) for item in report["scenarios"])
            / 1000.0,
            3,
        ),
    }


def validate_manifest(standard: dict, failures: list[str]) -> dict:
    specification = standard["evidence_manifest"]
    manifest_path = ROOT / str(specification["path"]).removeprefix("res://")
    expect(manifest_path.is_file(), "CPU evidence manifest is missing", failures)
    if not manifest_path.is_file():
        return {}
    expect(
        sha256(manifest_path) == specification["sha256"],
        "CPU evidence manifest digest mismatch",
        failures,
    )
    manifest = load(manifest_path)
    expect(
        manifest.get("schema")
        == "world_transvoxel.terrain_lab.cpu_finalization_manifest.v1",
        "CPU evidence manifest schema mismatch",
        failures,
    )
    reports = manifest.get("reports", [])
    expect(
        manifest.get("report_count") == specification["report_count"] == len(reports),
        "CPU evidence report count mismatch",
        failures,
    )
    names = [item.get("name") for item in reports]
    expect(len(names) == len(set(names)), "CPU evidence manifest has duplicates", failures)
    for item in reports:
        path = EVIDENCE_ROOT / str(item.get("name", ""))
        expect(path.is_file(), f"retained CPU report missing: {path.name}", failures)
        if not path.is_file():
            continue
        expect(path.stat().st_size == item.get("bytes"), f"size mismatch: {path.name}", failures)
        expect(sha256(path) == item.get("sha256"), f"digest mismatch: {path.name}", failures)
    return manifest


def validate_report(
    report: dict,
    name: str,
    standard: dict,
    scenario_ids: list[str],
    native_mode: str,
    profile: str,
    generation_workers: int,
    meshing_workers: int,
    failures: list[str],
) -> None:
    baseline = standard["accepted_baselines"]["cpu_release"]
    expect(report.get("status") == "PASS", f"{name} did not pass", failures)
    expect(
        report.get("cpu_finalization_status") == "PASS",
        f"{name} is not a promotable CPU-finalization PASS",
        failures,
    )
    expect(report.get("retained_complete") is True, f"{name} is incomplete", failures)
    expect(report.get("failures") == [], f"{name} contains failures", failures)
    expect(
        report.get("candidate_revision") == baseline["candidate_revision"],
        f"{name} candidate revision mismatch",
        failures,
    )
    expect(
        report.get("authority_revision") == baseline["native_authority_revision"],
        f"{name} authority revision mismatch",
        failures,
    )
    execution = report.get("execution", {})
    expect(execution.get("native_mode") == native_mode, f"{name} mode mismatch", failures)
    expect(execution.get("profile") == profile, f"{name} profile mismatch", failures)
    expect(
        execution.get("generation_worker_count_actual") == generation_workers,
        f"{name} generation worker mismatch",
        failures,
    )
    expect(
        execution.get("meshing_worker_count") == meshing_workers,
        f"{name} meshing worker mismatch",
        failures,
    )
    expect(execution.get("frames_per_scenario", 0) >= 300, f"{name} has too few frames", failures)
    expect(execution.get("evidence_class") == "qualification", f"{name} is not qualification evidence", failures)
    expect(execution.get("promotable") is True, f"{name} is not promotable", failures)
    for key in (
        "logical_cpu_affinity",
        "launched_process_logical_cpu_affinity",
    ):
        expect(execution.get(key) == [0, 1, 2], f"{name} {key} mismatch", failures)
    expect(execution.get("logical_cpu_limit") == 3, f"{name} CPU limit mismatch", failures)
    expect(
        report.get("host", {}).get("process_logical_cpu_affinity") == [0, 1, 2],
        f"{name} host affinity mismatch",
        failures,
    )
    engine = report.get("engine", {})
    expect(engine.get("major") == 4 and engine.get("minor") == 7, f"{name} engine mismatch", failures)
    if native_mode == "release_runtime_4_7_1":
        expect(engine.get("patch") == 1, f"{name} release runtime is not Godot 4.7.1", failures)
    source = report.get("source_integrity", [])
    expect(len(source) == 2, f"{name} source-integrity boundary mismatch", failures)
    expect(
        all(item.get("qualification_clean") is True for item in source),
        f"{name} source tree was dirty",
        failures,
    )
    backend = report.get("backend_identity", {})
    expect(
        backend.get("backend_id") == "transvoxel_mit_official"
        and backend.get("mit_backend_available") is True
        and backend.get("missing_methods") == [],
        f"{name} authority backend mismatch",
        failures,
    )
    runtime_profile = report.get("profile", {})
    expect(
        runtime_profile.get("authority") == "world-transvoxel"
        and runtime_profile.get("fallback") is False,
        f"{name} used a fallback or wrong authority",
        failures,
    )
    scenarios = report.get("scenarios", [])
    expect([item.get("id") for item in scenarios] == scenario_ids, f"{name} scenario set mismatch", failures)
    for scenario in scenarios:
        scenario_id = str(scenario.get("id", "unknown"))
        expect(scenario.get("status") == "PASS", f"{name}/{scenario_id} failed", failures)
        expect(
            scenario.get("frame", {}).get("sample_count", 0) >= 300,
            f"{name}/{scenario_id} has too few frame samples",
            failures,
        )
    expect(report.get("collision", {}).get("status") == "PASS", f"{name} collision failed", failures)
    expect(report.get("persistence", {}).get("status") == "PASS", f"{name} persistence failed", failures)
    expect(report.get("shutdown", {}).get("status") == "PASS", f"{name} shutdown failed", failures)
    expect(report.get("final_lod_audit", {}).get("status") == "PASS", f"{name} LOD audit failed", failures)
    expect(report.get("lod_seam_audit", {}).get("status") == "PASS", f"{name} seam audit failed", failures)
    process = report.get("process_telemetry", {})
    expect(process.get("cpu_package_power_available") is False, f"{name} CPU power boundary changed", failures)
    expect(process.get("whole_system_power_available") is False, f"{name} system power boundary changed", failures)
    expect(process.get("gpu_board_power_is_cpu_power") is False, f"{name} conflates GPU and CPU power", failures)


def profile_summary(reports: list[dict]) -> dict:
    summaries = [run_summary(report) for report in reports]
    keys = summaries[0].keys()
    medians = {key: round(median(item[key] for item in summaries), 3) for key in keys}
    wall_values = [item["wall_seconds"] for item in summaries]
    cpu_values = [item["process_cpu_seconds"] for item in summaries]
    wall_spread = (max(wall_values) - min(wall_values)) / median(wall_values)
    cpu_spread = (max(cpu_values) - min(cpu_values)) / median(cpu_values)
    return {
        "repetitions": len(reports),
        "median": medians,
        "wall_relative_range": round(wall_spread, 4),
        "cpu_relative_range": round(cpu_spread, 4),
        "repeatable": wall_spread <= 0.35 and cpu_spread <= 0.20,
        "runs": summaries,
    }


def scenario_medians(reports: list[dict]) -> dict[str, dict]:
    result = {}
    for scenario_id in FULL_SCENARIOS:
        scenarios = [
            next(item for item in report["scenarios"] if item["id"] == scenario_id)
            for report in reports
        ]
        result[scenario_id] = {
            "frame_p99_ms": round(median(item["frame"]["p99_usec"] for item in scenarios) / 1000.0, 3),
            "frame_worst_ms": round(median(item["frame"]["worst_usec"] for item in scenarios) / 1000.0, 3),
            "first_visual_ms": round(
                median(item["initial_settlement"]["first_visual_latency_usec"] for item in scenarios) / 1000.0,
                3,
            ),
            "first_collision_ms": round(
                median(item["initial_settlement"]["first_collision_latency_usec"] for item in scenarios) / 1000.0,
                3,
            ),
            "settlement_ms": round(
                median(item["initial_settlement"]["settlement_latency_usec"] for item in scenarios) / 1000.0,
                3,
            ),
            "edit_first_visual_ms": round(
                median(item.get("edit", {}).get("first_visual_latency_usec", 0) for item in scenarios) / 1000.0,
                3,
            ),
            "edit_first_collision_ms": round(
                median(item.get("edit", {}).get("first_collision_latency_usec", 0) for item in scenarios) / 1000.0,
                3,
            ),
            "edit_total_ms": round(
                median(item.get("edit", {}).get("latency_usec", 0) for item in scenarios) / 1000.0,
                3,
            ),
        }
    return result


def target_assessment(standard: dict, scenarios: dict[str, dict]) -> dict:
    targets = standard["production_responsiveness_targets"]
    relocation = [
        "ground_traversal",
        "high_speed_flight",
        "vertical_cave",
        "adaptive_lod_churn",
        "cold_teleport",
        "far_return",
    ]
    movement = [
        "ground_traversal",
        "high_speed_flight",
        "vertical_cave",
        "adaptive_lod_churn",
    ]
    edits = ["digging", "construction"]

    def evaluate(name: str, target: float, observations: dict[str, float]) -> dict:
        misses = {key: value for key, value in observations.items() if value > target}
        return {
            "target": target,
            "observations": observations,
            "status": "PASS" if not misses else "MISS",
            "misses": misses,
        }

    assessments = {
        "sustained_frame_p99_ms": evaluate(
            "sustained_frame_p99_ms",
            float(targets["sustained_frame_p99_ms"]),
            {key: scenarios[key]["frame_p99_ms"] for key in FULL_SCENARIOS},
        ),
        "first_correct_visual_relocation_ms": evaluate(
            "first_correct_visual_relocation_ms",
            float(targets["first_correct_visual_relocation_ms"]),
            {key: scenarios[key]["first_visual_ms"] for key in relocation},
        ),
        "collision_coherence_ms": evaluate(
            "collision_coherence_ms",
            float(targets["collision_coherence_ms"]),
            {key: scenarios[key]["first_collision_ms"] for key in relocation},
        ),
        "local_edit_first_visual_ms": evaluate(
            "local_edit_first_visual_ms",
            float(targets["local_edit_first_visual_ms"]),
            {key: scenarios[key]["edit_first_visual_ms"] for key in edits},
        ),
        "local_edit_collision_ms": evaluate(
            "local_edit_collision_ms",
            float(targets["local_edit_collision_ms"]),
            {key: scenarios[key]["edit_first_collision_ms"] for key in edits},
        ),
        "local_edit_total_ms": evaluate(
            "local_edit_total_ms",
            float(targets["local_edit_total_ms"]),
            {key: scenarios[key]["edit_total_ms"] for key in edits},
        ),
        "cold_teleport_settlement_ms": evaluate(
            "cold_teleport_settlement_ms",
            float(targets["cold_teleport_settlement_ms"]),
            {"cold_teleport": scenarios["cold_teleport"]["settlement_ms"]},
        ),
        "sustained_movement_settlement_ms": evaluate(
            "sustained_movement_settlement_ms",
            float(targets["sustained_movement_settlement_ms"]),
            {key: scenarios[key]["settlement_ms"] for key in movement},
        ),
        "far_return_settlement_ms": evaluate(
            "far_return_settlement_ms",
            float(targets["far_return_settlement_ms"]),
            {"far_return": scenarios["far_return"]["settlement_ms"]},
        ),
    }
    return {
        "status": "PASS" if all(item["status"] == "PASS" for item in assessments.values()) else "MISS",
        "policy": targets["policy"],
        "assessments": assessments,
    }


def phase_medians(reports: list[dict]) -> dict[str, float]:
    return {
        phase: round(
            median(
                sum(
                    scenario["native_phase_frame_distributions"][phase]["total"]
                    for scenario in report["scenarios"]
                )
                for report in reports
            )
            / 1_000_000_000.0,
            3,
        )
        for phase in PHASES
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-eligible", action="store_true")
    arguments = parser.parse_args()

    standard = load(STANDARD_PATH)
    failures: list[str] = []
    expect(
        standard.get("schema")
        == "world_transvoxel.terrain_lab.cpu_finalization_standard.v2",
        "CPU finalization standard schema mismatch",
        failures,
    )
    manifest = validate_manifest(standard, failures)
    retained_names = {item.get("name") for item in manifest.get("reports", [])}

    required_names = set(C1_REPORTS.values())
    required_names.update(MESH_SWEEP.values())
    required_names.update(GENERATION_SWEEP.values())
    for names in PROFILE_REPORTS.values():
        required_names.update(names)
    required_names.update(
        {
            "cpu-c2-generation-g2-m2.json",
            "cpu-c3-profile-low-power-w1-runtime-result.json",
            "cpu-c3-profile-quality-w4-runtime-result.json",
            "dev-storage-completion-single-scan.json",
            "dev-worker-side-page-decode.json",
        }
    )
    expect(required_names == retained_names, "retained CPU evidence set mismatch", failures)

    reports = {name: load(EVIDENCE_ROOT / name) for name in retained_names if (EVIDENCE_ROOT / name).is_file()}
    for mode, name in C1_REPORTS.items():
        validate_report(
            reports[name],
            name,
            standard,
            FULL_SCENARIOS,
            mode,
            "balanced",
            2,
            2,
            failures,
        )
    for workers, name in MESH_SWEEP.items():
        validate_report(
            reports[name],
            name,
            standard,
            FOCUSED_SCENARIOS,
            "release_runtime_4_7_1",
            "balanced",
            2,
            workers,
            failures,
        )
    for workers, name in GENERATION_SWEEP.items():
        validate_report(
            reports[name],
            name,
            standard,
            FOCUSED_SCENARIOS,
            "release_runtime_4_7_1",
            "balanced",
            workers,
            2,
            failures,
        )
    profile_results = {}
    for profile, names in PROFILE_REPORTS.items():
        generation_workers, meshing_workers = PROFILE_WORKERS[profile]
        expected_scenarios = FULL_SCENARIOS if profile == "balanced" else FOCUSED_SCENARIOS
        group = [reports[name] for name in names]
        for name, report in zip(names, group, strict=True):
            validate_report(
                report,
                name,
                standard,
                expected_scenarios,
                "release_runtime_4_7_1",
                profile,
                generation_workers,
                meshing_workers,
                failures,
            )
        profile_results[profile] = profile_summary(group)
        expect(profile_results[profile]["repeatable"], f"{profile} profile is not repeatable", failures)

    mesh_summaries = {str(key): run_summary(reports[name]) for key, name in MESH_SWEEP.items()}
    generation_summaries = {
        str(key): run_summary(reports[name]) for key, name in GENERATION_SWEEP.items()
    }
    mesh_one, mesh_two, mesh_three = (mesh_summaries[str(key)] for key in (1, 2, 3))
    expect(mesh_two["wall_seconds"] < mesh_one["wall_seconds"], "two mesh workers did not beat one", failures)
    expect(
        mesh_three["wall_seconds"] >= mesh_two["wall_seconds"] * 0.98
        and mesh_three["maximum_scenario_frame_p99_ms"]
        > mesh_two["maximum_scenario_frame_p99_ms"],
        "two-worker mesh selection is not supported by the sweep",
        failures,
    )
    generation_one, generation_two, generation_three = (
        generation_summaries[str(key)] for key in (1, 2, 3)
    )
    expect(
        generation_two["wall_seconds"] < generation_one["wall_seconds"]
        and generation_two["wall_seconds"] < generation_three["wall_seconds"],
        "two-worker generation selection is not supported by wall time",
        failures,
    )
    expect(
        generation_two["maximum_scenario_frame_p99_ms"]
        < generation_three["maximum_scenario_frame_p99_ms"],
        "three generation workers do not show the retained tail regression",
        failures,
    )

    failed_low = reports["cpu-c3-profile-low-power-w1-runtime-result.json"]
    failed_quality = reports["cpu-c3-profile-quality-w4-runtime-result.json"]
    expect(
        failed_low.get("status") == "FAIL" and failed_low.get("failures"),
        "historical low-power failure was not retained",
        failures,
    )
    expect(
        failed_quality.get("status") == "FAIL" and failed_quality.get("failures"),
        "historical quality failure was not retained",
        failures,
    )
    historical_base = run_summary(reports["cpu-c2-generation-g2-m2.json"])
    rejected = {}
    for name in (
        "dev-storage-completion-single-scan.json",
        "dev-worker-side-page-decode.json",
    ):
        report = reports[name]
        summary = run_summary(report)
        expect(
            report.get("cpu_finalization_status") == "DEVELOPMENT_PASS"
            and any(
                not item.get("qualification_clean", True)
                for item in report.get("source_integrity", [])
            ),
            f"{name} is not retained as dirty development evidence",
            failures,
        )
        expect(
            summary["wall_seconds"] > historical_base["wall_seconds"]
            and summary["maximum_scenario_frame_p99_ms"]
            > historical_base["maximum_scenario_frame_p99_ms"],
            f"{name} did not reproduce its measured rejection",
            failures,
        )
        rejected[name] = summary

    authority = REPOSITORY_ROOT / "world-transvoxel"
    revision = standard["accepted_baselines"]["cpu_release"]["native_authority_revision"]
    worker_source = git_show(
        authority,
        revision,
        "addons/world_transvoxel/src/services/wt_page_meshing_runtime.cpp",
    )
    for signature in (
        "struct WtPageMeshingRuntimeService::PreparedMeshJob",
        "std::vector<std::thread> workers",
        "mesh_worker_cancelled_queued_jobs",
        "mesh_worker_reprioritized_queued_jobs",
        "execute_prepared_mesh_job",
    ):
        expect(signature in worker_source, f"authority worker signature missing: {signature}", failures)

    stages = [
        {
            "id": stage["id"],
            "title": stage["title"],
            "status": stage["status"],
            "depends_on": stage.get("depends_on", []),
            "evidence": stage.get("evidence", []),
        }
        for stage in standard["ordered_closure"]
    ]
    expect(
        [stage["id"] for stage in stages] == ["CPU-C1", "CPU-C2", "CPU-C3"],
        "CPU closure order mismatch",
        failures,
    )
    expect(all(stage["status"] == "qualified" for stage in stages), "CPU closure is not qualified", failures)
    expect(standard.get("current_known_blockers") == [], "CPU finalization blockers remain", failures)
    expect(
        len(standard.get("remaining_bottleneck_classification", [])) >= 5,
        "remaining bottlenecks are not classified",
        failures,
    )

    final_reports = [reports[name] for name in PROFILE_REPORTS["balanced"]]
    scenarios = scenario_medians(final_reports)
    targets = target_assessment(standard, scenarios)
    gate_passed = not failures
    result = {
        "schema": "world_transvoxel.terrain_lab.cpu_finalization_readiness.v2",
        "date": "2026-08-09",
        "gate_id": standard["gate_id"],
        "status": "PASS" if gate_passed else "FAIL",
        "retained_complete": gate_passed,
        "tqp58_eligible": gate_passed,
        "standard": {
            "path": STANDARD_PATH.relative_to(ROOT).as_posix(),
            "sha256": sha256(STANDARD_PATH),
        },
        "evidence_manifest": standard["evidence_manifest"],
        "qualification_boundary": standard["qualification_boundary"],
        "accepted_cpu_release": standard["accepted_baselines"]["cpu_release"],
        "c1_mode_comparison": {
            mode: run_summary(reports[name]) for mode, name in C1_REPORTS.items()
        },
        "c2_worker_sweeps": {
            "selected_generation_workers": 2,
            "selected_meshing_workers": 2,
            "meshing": mesh_summaries,
            "generation": generation_summaries,
        },
        "profile_repeatability": profile_results,
        "final_balanced_scenario_medians": scenarios,
        "production_target_assessment": targets,
        "final_balanced_phase_median_seconds": phase_medians(final_reports),
        "remaining_bottleneck_classification": standard[
            "remaining_bottleneck_classification"
        ],
        "known_target_misses": standard["known_target_misses"],
        "power_boundaries": standard["power_boundaries"],
        "historical_excluded_evidence": {
            "pre_affinity_comparison_baseline": historical_base,
            "rejected_optimizations": rejected,
            "failed_profile_reports": {
                "low_power": failed_low.get("failures", []),
                "quality": failed_quality.get("failures", []),
            },
        },
        "ordered_closure": stages,
        "consistency_failures": failures,
        "decision": (
            "CPU-C1 through CPU-C3 pass under the retained three-logical-CPU boundary. "
            "TQP-58 is eligible for a measured architecture decision. CPU remains the "
            "correctness authority, and recorded performance target misses prevent any "
            "claim that CPU terrain performance is complete."
            if gate_passed
            else "CPU finalization evidence is inconsistent; TQP-58 remains ineligible."
        ),
    }
    RESULT_PATH.write_text(json.dumps(result, indent="\t") + "\n", encoding="utf-8")

    if failures:
        for failure in failures:
            print("WT_TERRAIN_CPU_FINALIZATION_AUDIT_FAIL " + failure)
        return 1
    if arguments.require_eligible and not gate_passed:
        return 1
    print(
        "WT_TERRAIN_CPU_FINALIZATION_AUDIT_PASS "
        "stages=CPU-C1,CPU-C2,CPU-C3 logical_cpus=3 "
        f"targets={targets['status']} tqp58_eligible=1"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
