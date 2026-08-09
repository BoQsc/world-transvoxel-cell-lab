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

    matrix_contract = source(candidate, matrix_standard["source_contract"], failures, "TQP-55 contract")
    matrix_report = source(candidate, matrix_standard["source_report"], failures, "TQP-55 report")
    long_contract = source(candidate, long_standard["source_contract"], failures, "TQP-56 contract")
    long_report = source(candidate, long_standard["source_report"], failures, "TQP-56 report")
    release_contract = source(candidate, release_standard["source_contract"], failures, "TQP-57 contract")
    release_report = source(candidate, release_standard["source_report"], failures, "TQP-57 report")
    manifest = source(candidate, release_standard["manifest"], failures, "TQP-57 manifest")
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
            "TQP-57": {"status": "PASS" if not failures else "FAIL", "standard_id": release_standard["standard_id"], "release_id": release_standard["release_id"], "version": release_standard["version"], "release_boundary": release_standard["release_boundary"], "package": package},
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
