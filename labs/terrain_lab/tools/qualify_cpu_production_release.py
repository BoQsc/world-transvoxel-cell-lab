from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[3]
REPOSITORY_ROOT = ROOT.parent
STANDARDS = ROOT / "addons/world_transvoxel_terrain_lab/standards"
RESULT = ROOT / "labs/terrain_lab/results/cpu_production_release_reference_windows.json"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(repo: Path, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-c", f"safe.directory={repo.as_posix()}", "-C", str(repo), *arguments],
        text=True,
        capture_output=True,
        check=check,
    )


def git_value(repo: Path, revision: str) -> str:
    return git(repo, "rev-parse", revision).stdout.strip()


def tracked_clean(repo: Path) -> bool:
    return git(repo, "diff", "--quiet", check=False).returncode == 0 and git(repo, "diff", "--cached", "--quiet", check=False).returncode == 0


def source(repo: Path, spec: dict, failures: list[str], label: str) -> dict:
    path = repo / spec["path"]
    if not path.is_file():
        failures.append(f"{label} missing: {spec['path']}")
        return {}
    if sha256(path) != spec["sha256"]:
        failures.append(f"{label} digest mismatch")
    try:
        return load(path)
    except (OSError, ValueError) as error:
        failures.append(f"{label} invalid JSON: {error}")
        return {}


def main() -> int:
    matrix_standard = load(STANDARDS / "cpu_production_release_matrix_standard.json")
    long_standard = load(STANDARDS / "cpu_production_long_haul_standard.json")
    release_standard = load(STANDARDS / "cpu_production_release_standard.json")
    candidate = REPOSITORY_ROOT / matrix_standard["candidate"]["repository"]
    authority = REPOSITORY_ROOT / matrix_standard["native_authority"]["repository"]
    integration = REPOSITORY_ROOT / matrix_standard["integration"]["repository"]
    failures: list[str] = []

    for label, repo in (("candidate", candidate), ("authority", authority), ("integration", integration)):
        if not repo.is_dir():
            failures.append(f"{label} repository missing")
        elif not tracked_clean(repo):
            failures.append(f"{label} repository has tracked content changes")

    candidate_revision = git_value(candidate, "HEAD")
    candidate_tree = git_value(candidate, "HEAD:addons/world_transvoxel_terrain")
    authority_revision = git_value(authority, "HEAD")
    integration_revision = git_value(integration, "HEAD")
    if candidate_revision != matrix_standard["candidate"]["revision"]:
        failures.append("candidate revision mismatch")
    if candidate_tree != matrix_standard["candidate"]["addon_tree"]:
        failures.append("candidate addon tree mismatch")
    if authority_revision != matrix_standard["native_authority"]["revision"]:
        failures.append("native authority revision mismatch")
    if integration_revision != matrix_standard["integration"]["revision"]:
        failures.append("integration revision mismatch")
    if long_standard["candidate_revision"] != candidate_revision:
        failures.append("TQP-56 candidate revision mismatch")
    if release_standard["candidate_revision"] != candidate_revision:
        failures.append("TQP-57 candidate revision mismatch")
    if release_standard["candidate_addon_tree"] != candidate_tree:
        failures.append("TQP-57 candidate addon tree mismatch")
    if release_standard["integration_revision"] != integration_revision:
        failures.append("TQP-57 integration revision mismatch")

    matrix_contract = source(candidate, matrix_standard["source_contract"], failures, "TQP-55 contract")
    matrix_report = source(candidate, matrix_standard["source_report"], failures, "TQP-55 report")
    long_contract = source(candidate, long_standard["source_contract"], failures, "TQP-56 contract")
    long_report = source(candidate, long_standard["source_report"], failures, "TQP-56 report")
    release_contract = source(candidate, release_standard["source_contract"], failures, "TQP-57 contract")
    release_report = source(candidate, release_standard["source_report"], failures, "TQP-57 report")
    manifest = source(candidate, release_standard["manifest"], failures, "TQP-57 manifest")
    large_standard = release_standard["large_terrain_acceptance"]
    large_contract = source(candidate, large_standard["contract"], failures, "TQP-57 large-terrain contract")
    large_report = source(candidate, large_standard["report"], failures, "TQP-57 large-terrain report")
    package_path = candidate / release_standard["package"]["path"]
    if not package_path.is_file() or sha256(package_path) != release_standard["package"]["zip_sha256"]:
        failures.append("TQP-57 release ZIP mismatch")

    if matrix_contract.get("supported_matrix") != matrix_standard["required_matrix"] | {
        "execution_modes": matrix_contract.get("supported_matrix", {}).get("execution_modes", []),
        "hardware_classes": matrix_contract.get("supported_matrix", {}).get("hardware_classes", []),
        "upgrade_policy": matrix_contract.get("supported_matrix", {}).get("upgrade_policy", ""),
    }:
        for key, value in matrix_standard["required_matrix"].items():
            if matrix_contract.get("supported_matrix", {}).get(key) != value:
                failures.append(f"TQP-55 matrix mismatch: {key}")
    if matrix_report.get("status") != "PASS" or matrix_report.get("base_revision") != candidate_revision:
        failures.append("TQP-55 report status or revision mismatch")
    if matrix_report.get("package", {}).get("package_digest_sha256") != release_standard["package"]["package_digest_sha256"]:
        failures.append("TQP-55 package digest mismatch")
    if matrix_report.get("power_target_status") != matrix_standard["power_target_status"]:
        failures.append("TQP-55 power target status was widened")

    workload = long_report.get("workload", {})
    if long_report.get("status") != "PASS" or long_report.get("engine") != "4.7":
        failures.append("TQP-56 report failed")
    for key in ("cycles", "edits", "queries", "restarts"):
        if int(workload.get(key, 0)) < int(long_standard[f"minimum_{key}"]):
            failures.append(f"TQP-56 {key} coverage incomplete")
    if float(workload.get("duration_seconds", 0)) < long_standard["minimum_wrapper_duration_seconds"]:
        failures.append("TQP-56 duration incomplete")
    if int(workload.get("memory_growth_bytes", -1)) > long_standard["maximum_memory_growth_bytes"]:
        failures.append("TQP-56 memory growth failed")
    if int(workload.get("queue_rejections", -1)) > long_standard["maximum_queue_rejections"]:
        failures.append("TQP-56 queue rejection budget failed")
    retained = long_report.get("retained_long_run", {})
    if retained.get("minimum_rendered_seconds") != long_standard["retained_native_seconds"] or retained.get("minimum_frame_samples") != long_standard["retained_frame_samples"]:
        failures.append("TQP-56 retained long-run boundary mismatch")

    package = release_standard["package"]
    if release_report.get("status") != "PASS" or release_report.get("base_revision") != candidate_revision:
        failures.append("TQP-57 report status or revision mismatch")
    if release_report.get("package", {}).get("zip_sha256") != package["zip_sha256"]:
        failures.append("TQP-57 release report ZIP mismatch")
    if manifest.get("package", {}).get("package_digest_sha256") != package["package_digest_sha256"] or len(manifest.get("files", [])) != package["files"]:
        failures.append("TQP-57 manifest mismatch")

    large_authority = large_contract.get("authority", {})
    if (
        large_contract.get("engine") != "4.7"
        or large_contract.get("renderer") != "forward_plus"
        or large_authority.get("revision") != authority_revision
        or large_authority.get("fallback_mesher") is not False
        or large_authority.get("fallback_field") is not False
    ):
        failures.append("TQP-57 large-terrain authority or engine contract mismatch")
    if large_report.get("status") != "PASS" or large_report.get("base_revision") != candidate_revision:
        failures.append("TQP-57 large-terrain report status or revision mismatch")
    if large_report.get("retained_complete") is not True or large_report.get("failures") != []:
        failures.append("TQP-57 large-terrain report is not retained complete")
    large_profile = large_report.get("profile", {})
    if (
        large_profile.get("volume_cells") != large_standard["volume_cells"]
        or large_profile.get("volume_chunks") != large_standard["volume_chunks"]
        or large_profile.get("fallback") is not False
        or large_profile.get("authority") != "world-transvoxel"
    ):
        failures.append("TQP-57 large-terrain profile mismatch")
    observed_lods = {
        int(level)
        for level, count in large_report.get("observed_lod_counts", {}).items()
        if int(count) > 0
    }
    if observed_lods != set(large_standard["required_lod_levels"]):
        failures.append("TQP-57 required live LOD levels were not all observed")
    scenarios = {
        item.get("id"): item.get("status")
        for item in large_report.get("scenarios", [])
    }
    if scenarios != {
        scenario_id: "PASS" for scenario_id in large_standard["required_scenarios"]
    }:
        failures.append("TQP-57 assembled scenario matrix mismatch")
    captures = {
        item.get("id"): item.get("status")
        for item in large_report.get("captures", [])
    }
    if captures != {
        capture_id: "PASS" for capture_id in large_standard["required_capture_ids"]
    }:
        failures.append("TQP-57 retained capture matrix mismatch")
    seam_audit = large_report.get("lod_seam_audit", {})
    topology = seam_audit.get("topology", {})
    for metric in (
        "boundary_edges",
        "nonmanifold_edges",
        "orientation_inconsistent_edges",
        "zero_area_triangles",
    ):
        budget = large_standard[f"maximum_topology_{metric}"]
        observed = int(topology.get(metric, -1))
        if observed < 0 or observed > int(budget):
            failures.append(f"TQP-57 LOD seam topology failed: {metric}")
    if (
        seam_audit.get("status") != "PASS"
        or seam_audit.get("lod_seam", {}).get("found") is not True
    ):
        failures.append("TQP-57 live mixed-LOD seam was not qualified")
    if large_report.get("collision", {}).get("status") != "PASS":
        failures.append("TQP-57 targeted collision acceptance failed")
    if large_report.get("persistence", {}).get("status") != "PASS":
        failures.append("TQP-57 edit persistence acceptance failed")

    large_budgets = large_standard["budgets"]
    contract_budgets = large_contract.get("budgets", {})
    for budget_name, expected in large_budgets.items():
        if contract_budgets.get(budget_name) != expected:
            failures.append(f"TQP-57 large-terrain contract budget mismatch: {budget_name}")
    catalog_pages = int(large_report.get("initial_snapshot", {}).get("catalog_page_count", 0))
    if catalog_pages < int(large_budgets["minimum_catalog_pages"]):
        failures.append("TQP-57 large-terrain catalog coverage failed")
    frame_envelope = large_report.get("aggregate", {}).get("frame_envelope", {})
    if float(frame_envelope.get("p99_usec", -1.0)) < 0.0 or float(
        frame_envelope.get("p99_usec", -1.0)
    ) > float(large_budgets["maximum_frame_p99_usec"]):
        failures.append("TQP-57 large-terrain frame p99 budget failed")
    memory = large_report.get("memory", {})
    if int(memory.get("peak_static_bytes", -1)) < 0 or int(
        memory.get("peak_static_bytes", -1)
    ) > int(large_budgets["maximum_peak_process_memory_bytes"]):
        failures.append("TQP-57 large-terrain memory budget failed")
    queue_peaks = large_report.get("queue_peaks", {})
    for queue_name in ("scheduler", "storage", "render", "collision"):
        budget = large_budgets[f"maximum_{queue_name}_queue_depth"]
        observed = int(queue_peaks.get(queue_name, -1))
        if observed < 0 or observed > int(budget):
            failures.append(f"TQP-57 large-terrain queue budget failed: {queue_name}")
    final_lod_audit = large_report.get("final_lod_audit", {})
    overlap_count = int(final_lod_audit.get("coverage_overlap_count", -1))
    if overlap_count < 0 or overlap_count > int(large_budgets["maximum_coverage_overlaps"]):
        failures.append("TQP-57 large-terrain adaptive coverage overlap failed")
    generation_mismatches = len(final_lod_audit.get("visual_generation_mismatches", []))
    generation_mismatches += len(final_lod_audit.get("collision_generation_mismatches", []))
    if generation_mismatches > int(large_budgets["maximum_generation_mismatches"]):
        failures.append("TQP-57 large-terrain generation coherence failed")
    integration_pin = integration / "TQP54_PACKAGE_PIN.json"
    if sha256(integration_pin) != release_standard["integration_package_pin_sha256"]:
        failures.append("final integration package pin mismatch")
    else:
        pin = load(integration_pin)
        if pin.get("candidate", {}).get("commit") != candidate_revision or pin.get("candidate", {}).get("addon_tree") != candidate_tree or pin.get("candidate", {}).get("package_digest_sha256") != package["package_digest_sha256"]:
            failures.append("final integration candidate pin mismatch")

    evidence = {
        "schema": "world_transvoxel.terrain_lab.cpu_production_release_qualification.v1",
        "date": "2026-08-09",
        "status": "PASS" if not failures else "FAIL",
        "retained_complete": not failures,
        "gate": "GATE_F",
        "gate_promoted": not failures,
        "candidate": {"revision": candidate_revision, "addon_tree": candidate_tree, "tracked_content_clean": tracked_clean(candidate)},
        "native_authority": {"revision": authority_revision, "tracked_content_clean": tracked_clean(authority)},
        "integration": {"revision": integration_revision, "tracked_content_clean": tracked_clean(integration)},
        "milestones": {
            "TQP-55": {"status": "PASS" if not failures else "FAIL", "standard_id": matrix_standard["standard_id"], "matrix": matrix_standard["required_matrix"], "package_digest_sha256": package["package_digest_sha256"], "power_target_status": matrix_standard["power_target_status"]},
            "TQP-56": {"status": "PASS" if not failures else "FAIL", "standard_id": long_standard["standard_id"], "workload": workload, "retained_native_seconds": long_standard["retained_native_seconds"], "retained_frame_samples": long_standard["retained_frame_samples"]},
            "TQP-57": {
                "status": "PASS" if not failures else "FAIL",
                "standard_id": release_standard["standard_id"],
                "release_id": release_standard["release_id"],
                "version": release_standard["version"],
                "release_boundary": release_standard["release_boundary"],
                "package": package,
                "large_terrain_acceptance": {
                    "volume_cells": large_standard["volume_cells"],
                    "volume_chunks": large_standard["volume_chunks"],
                    "source_contract_sha256": large_standard["contract"]["sha256"],
                    "source_report_sha256": large_standard["report"]["sha256"],
                    "catalog_page_count": catalog_pages,
                    "observed_lod_counts": large_report.get("observed_lod_counts", {}),
                    "frame_envelope": frame_envelope,
                    "memory": memory,
                    "queue_peaks": queue_peaks,
                    "coverage_overlap_count": overlap_count,
                    "generation_mismatch_count": generation_mismatches,
                    "scenarios": scenarios,
                    "captures": captures,
                    "lod_seam": seam_audit.get("lod_seam", {}),
                    "topology": {
                        metric: topology.get(metric)
                        for metric in (
                            "boundary_edges",
                            "nonmanifold_edges",
                            "orientation_inconsistent_edges",
                            "zero_area_triangles",
                        )
                    },
                    "collision": large_report.get("collision", {}).get("status"),
                    "persistence": large_report.get("persistence", {}).get("status"),
                },
            },
        },
        "qualified_scope": matrix_standard["qualified_scope"] + long_standard["qualified_scope"] + release_standard["qualified_scope"],
        "explicitly_unqualified_scope": release_standard["explicitly_unqualified_scope"],
        "next_milestone": "TQP-58",
        "failures": failures,
    }
    RESULT.write_text(json.dumps(evidence, indent="\t") + "\n", encoding="utf-8")
    if failures:
        for failure in failures:
            print("WT_TERRAIN_CPU_PRODUCTION_RELEASE_FAIL " + failure)
        return 1
    print(
        "WT_TERRAIN_CPU_PRODUCTION_RELEASE_PASS "
        f"candidate={candidate_revision} integration={integration_revision} "
        "milestones=TQP-55,TQP-56,TQP-57 gate=GATE_F next=TQP-58"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
