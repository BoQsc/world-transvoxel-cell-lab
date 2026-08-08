#!/usr/bin/env python3
"""Fail-closed aggregation for TQP-49 soak recovery and TQP-50 Gate E."""

from __future__ import annotations

import hashlib
import json
import pathlib
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[3]
STANDARDS = ROOT / "addons/world_transvoxel_terrain_lab/standards"
RESULTS = ROOT / "labs/terrain_lab/results"


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else "MISSING"


def accepted_visual(report: dict[str, Any]) -> bool:
    categories = report.get("categories", {})
    standard = load(STANDARDS / "complex_visual_temporal_corpus_standard.json")
    automation = load(
        RESULTS / "complex_visual_temporal_corpus_automation_windows.json"
    )
    required = standard.get("coverage_contract", {}).get(
        "required_review_categories", []
    )
    still_ids = sorted(item.get("id") for item in automation.get("stills", []))
    motion_ids = sorted(
        item.get("id") for item in automation.get("motion_paths", [])
    )
    live_scenes = sorted(
        {
            item.get("scene")
            for group in [
                automation.get("stills", []),
                automation.get("motion_paths", []),
            ]
            for item in group
            if item.get("scene")
        }
    )
    return (
        report.get("status") == "PASS"
        and bool(report.get("reviewer"))
        and bool(report.get("reviewed_at"))
        and automation.get("status") == "PASS_AUTOMATION_PENDING_HUMAN"
        and report.get("corpus_signature") == automation.get("corpus_signature")
        and bool(required)
        and all(categories.get(name) == "PASS" for name in required)
        and sorted(report.get("reviewed_still_ids", [])) == still_ids
        and sorted(report.get("reviewed_motion_path_ids", [])) == motion_ids
        and sorted(report.get("requested_live_scenes", [])) == live_scenes
    )


def complete_power(report: dict[str, Any]) -> bool:
    checks = report.get("protocol_checks", {})
    standard = load(STANDARDS / "low_power_qualification_standard.json")
    contract = standard.get("measurement", {})
    workload = report.get("workload", {})
    warmup = workload.get("warmup", {})
    measurement = workload.get("measurement", {})
    return (
        bool(report.get("retained_complete"))
        and report.get("status") in {"PASS", "MEASURED_TARGET_MISS"}
        and report.get("power_boundary")
        in {"soc_or_package", "complete_system_at_battery_or_dc_input"}
        and bool(checks)
        and all(bool(value) for value in checks.values())
        and report.get("profile_id") == "low_power_16w_60fps"
        and workload.get("profile")
        == standard.get("profiles", {}).get("low_power_16w_60fps")
        and int(warmup.get("requested_seconds", 0))
        == int(contract.get("warmup_seconds", -1))
        and float(warmup.get("elapsed_seconds", 0.0))
        >= float(contract.get("warmup_seconds", -1))
        and int(measurement.get("requested_seconds", 0))
        == int(contract.get("steady_state_seconds", -1))
        and float(measurement.get("elapsed_seconds", 0.0))
        >= float(contract.get("steady_state_seconds", -1))
        and int(measurement.get("frame_count", 0))
        >= int(contract.get("minimum_frame_samples", -1))
    )


def evidence_record(name: str, path: pathlib.Path, report: dict[str, Any], accepted: bool) -> dict[str, Any]:
    return {"name": name, "path": path.relative_to(ROOT).as_posix(), "schema": report.get("schema", "MISSING"), "reported_status": report.get("status", "MISSING"), "accepted": accepted, "sha256": sha256(path)}


def build_tqp49() -> dict[str, Any]:
    standard = load(STANDARDS / "complex_adaptive_soak_recovery_standard.json")
    paths = {name: ROOT / value.removeprefix("res://") for name, value in standard.get("required_evidence", {}).items()}
    reports = {name: load(path) for name, path in paths.items()}
    checks = {
        "native_soak": reports["native_soak"].get("status") == "PASS" and reports["native_soak"].get("native_soak", {}).get("status") == "PASS" and int(reports["native_soak"].get("native_soak", {}).get("requested_duration_seconds", 0)) >= 60,
        "large_world_soak": reports["large_world_soak"].get("status") == "PASS",
        "persistence": reports["persistence"].get("status") == "PASS" and bool(reports["persistence"].get("retained_complete", False)),
        "fault_recovery": reports["fault_recovery"].get("status") == "PASS" and bool(reports["fault_recovery"].get("retained_complete", False)),
        "visual_review": accepted_visual(reports["visual_review"]),
        "fast_arrival": reports["fast_arrival"].get("status") == "PASS" and bool(reports["fast_arrival"].get("retained_complete", False)),
        "collision": reports["collision"].get("status") == "PASS" and bool(reports["collision"].get("retained_complete", False)),
        "performance": reports["performance"].get("status") == "PASS" and bool(reports["performance"].get("retained_complete", False)),
        "power_long_run": complete_power(reports["power_long_run"])
        and reports["power_long_run"].get("drift_qualification", {}).get("status")
        == "PASS",
    }
    power_workload = reports["power_long_run"].get("workload", {})
    measurement = power_workload.get("measurement", {})
    temporal = {
        "complex_rendered_seconds": float(measurement.get("elapsed_seconds", 0.0)),
        "frame_samples": int(measurement.get("frame_count", 0)),
        "native_soak_seconds": int(reports["native_soak"].get("native_soak", {}).get("requested_duration_seconds", 0)),
        "memory_drift": reports["power_long_run"].get("drift_qualification", {}).get("memory", "PENDING_EXACT_TQP48_RUN"),
        "queue_drift": reports["power_long_run"].get("drift_qualification", {}).get("queues", "PENDING_EXACT_TQP48_RUN"),
        "frame_drift": reports["power_long_run"].get("drift_qualification", {}).get("frame_p99", "PENDING_EXACT_TQP48_RUN"),
        "thermal_drift": reports["power_long_run"].get("thermal", {}) if checks["power_long_run"] else "PENDING_EXACT_TQP48_RUN",
        "power_drift": reports["power_long_run"].get("power", {}) if checks["power_long_run"] else "PENDING_EXACT_TQP48_RUN",
    }
    blockers = [name for name, accepted in checks.items() if not accepted]
    status = "PASS" if not blockers else "BLOCKED_DEPENDENCIES"
    return {
        "schema": "world_transvoxel.terrain_lab.complex_adaptive_soak_recovery_qualification.v1",
        "milestone": "TQP-49", "standard_id": standard.get("standard_id"),
        "status": status, "retained_complete": not blockers,
        "evidence": [evidence_record(name, paths[name], reports[name], checks[name]) for name in paths],
        "coverage": checks, "temporal_drift": temporal,
        "recovery_contract": {"persistence_restart": checks["persistence"], "controlled_failure_recovery": checks["fault_recovery"], "clean_native_shutdown": checks["native_soak"]},
        "qualified_scope": standard.get("qualified_scope", []) if not blockers else [],
        "explicitly_unqualified_scope": standard.get("explicitly_unqualified_scope", []),
        "blockers": blockers,
    }


def build_tqp50(tqp49: dict[str, Any]) -> dict[str, Any]:
    standard = load(STANDARDS / "native_adaptive_authority_gate_standard.json")
    manifest_path = STANDARDS / "program_manifest.json"
    manifest = load(manifest_path)
    milestone_status = {item.get("id"): item.get("status") for item in manifest.get("milestones", [])}
    retained = {
        "TQP-44": accepted_visual(load(RESULTS / "complex_visual_temporal_corpus_human_review_windows.json")),
        "TQP-45": load(RESULTS / "fast_arrival_responsiveness_reference_windows.json").get("status") == "PASS",
        "TQP-46": load(RESULTS / "targeted_collision_residency_reference_windows.json").get("status") == "PASS",
        "TQP-47": load(RESULTS / "large_world_performance_reference_windows.json").get("status") == "PASS",
        "TQP-48": complete_power(load(RESULTS / "low_power_profiles_reference_windows.json")),
        "TQP-49": tqp49.get("status") == "PASS" and bool(tqp49.get("retained_complete")),
    }
    matrix: dict[str, dict[str, Any]] = {}
    for milestone in standard.get("required_milestones", []):
        number = int(milestone.split("-")[1])
        if number <= 43:
            accepted = milestone_status.get(milestone) == "qualified"
            source = "program_manifest_qualified_retained_evidence"
        else:
            accepted = retained.get(milestone, False)
            source = "focused_closure_evidence"
        matrix[milestone] = {"accepted": accepted, "source": source}
    blockers = [milestone for milestone, record in matrix.items() if not record["accepted"]]
    finding_reports = [load(path) | {"path": path.relative_to(ROOT).as_posix()} for path in sorted(STANDARDS.glob("*finding.json"))]
    open_findings = [item for item in finding_reports if not str(item.get("status", "")).startswith("CLOSED")]
    if open_findings:
        blockers.append("open_findings")
    gate_pass = not blockers
    return {
        "schema": "world_transvoxel.terrain_lab.native_adaptive_terrain_authority_gate.v1",
        "milestone": "TQP-50", "gate": "GATE_E", "standard_id": standard.get("standard_id"),
        "status": "PASS" if gate_pass else "BLOCKED",
        "gate_promoted": gate_pass, "retained_complete": gate_pass,
        "pinned_manifest": {"path": manifest_path.relative_to(ROOT).as_posix(), "program_revision": manifest.get("program_revision"), "sha256": sha256(manifest_path)},
        "milestone_matrix": matrix, "authority_matrix": standard.get("authority_matrix", {}),
        "open_findings": open_findings, "promotion_rules": standard.get("promotion_rules", []),
        "blockers": blockers,
        "next_action": "complete the listed fail-closed evidence; rerun this evaluator; do not promote Gate E before it reports PASS",
    }


def write(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    tqp49 = build_tqp49()
    tqp50 = build_tqp50(tqp49)
    write(RESULTS / "complex_adaptive_soak_recovery_reference_windows.json", tqp49)
    write(RESULTS / "native_adaptive_terrain_authority_gate_windows.json", tqp50)
    print(json.dumps({"TQP-49": tqp49["status"], "TQP-49 blockers": tqp49["blockers"], "TQP-50": tqp50["status"], "TQP-50 blockers": tqp50["blockers"]}, indent=2))
    return 0 if tqp50["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
