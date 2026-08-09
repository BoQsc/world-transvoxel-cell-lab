from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REPOSITORY_ROOT = ROOT.parent
STANDARDS_ROOT = (
    ROOT / "addons" / "world_transvoxel_terrain_lab" / "standards"
)
OUTPUT_PATH = (
    ROOT
    / "labs"
    / "terrain_lab"
    / "results"
    / "cpu_production_first_batch_reference_windows.json"
)
STANDARD_PATHS = {
    "TQP-52": STANDARDS_ROOT / "production_runtime_contract_standard.json",
    "TQP-53": STANDARDS_ROOT / "production_authoring_workflow_standard.json",
    "TQP-54": STANDARDS_ROOT / "downstream_migration_standard.json",
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-c", f"safe.directory={repo.as_posix()}", *args],
        cwd=repo,
        capture_output=True,
        text=True,
        check=check,
    )


def git_output(repo: Path, *args: str) -> str:
    return git(repo, *args).stdout.strip()


def tracked_content_clean(repo: Path) -> bool:
    return (
        git(repo, "diff", "--quiet", check=False).returncode == 0
        and git(repo, "diff", "--cached", "--quiet", check=False).returncode == 0
    )


def check_source(
    repo: Path,
    source: dict,
    failures: list[str],
    label: str,
) -> tuple[Path, dict]:
    path = repo / source["path"]
    if not path.is_file():
        failures.append(f"{label} source missing: {source['path']}")
        return path, {}
    if sha256(path) != source["sha256"]:
        failures.append(f"{label} source digest mismatch: {source['path']}")
    try:
        return path, load_json(path)
    except (OSError, ValueError) as error:
        failures.append(f"{label} source is invalid JSON: {error}")
        return path, {}


def engine_markers(report: dict) -> dict[str, str]:
    return {
        str(item.get("engine", "")): str(item.get("marker", ""))
        for item in report.get("engines", [])
    }


def main() -> int:
    standards = {key: load_json(path) for key, path in STANDARD_PATHS.items()}
    runtime_standard = standards["TQP-52"]
    authoring_standard = standards["TQP-53"]
    migration_standard = standards["TQP-54"]
    candidate = REPOSITORY_ROOT / runtime_standard["candidate"]["repository"]
    authority = REPOSITORY_ROOT / runtime_standard["native_authority"]["repository"]
    integration = REPOSITORY_ROOT / migration_standard["integration"]["repository"]
    failures: list[str] = []

    for label, repo in [
        ("candidate", candidate),
        ("native authority", authority),
        ("integration", integration),
    ]:
        if not repo.is_dir():
            failures.append(f"{label} repository missing: {repo}")

    candidate_revision = git_output(candidate, "rev-parse", "HEAD") if candidate.is_dir() else ""
    authority_revision = git_output(authority, "rev-parse", "HEAD") if authority.is_dir() else ""
    integration_revision = git_output(integration, "rev-parse", "HEAD") if integration.is_dir() else ""
    candidate_tree = (
        git_output(candidate, "rev-parse", f"HEAD:{runtime_standard['candidate']['addon_root']}")
        if candidate.is_dir()
        else ""
    )
    if candidate_revision != runtime_standard["candidate"]["revision"]:
        failures.append("candidate revision does not match the TQP-52/TQP-53 pin")
    if candidate_tree != runtime_standard["candidate"]["addon_tree"]:
        failures.append("candidate addon tree does not match the TQP-52/TQP-53 pin")
    if authority_revision != runtime_standard["native_authority"]["revision"]:
        failures.append("native authority revision does not match the retained pin")
    if integration_revision != migration_standard["integration"]["revision"]:
        failures.append("integration revision does not match the TQP-54 pin")
    for label, repo in [("candidate", candidate), ("authority", authority), ("integration", integration)]:
        if repo.is_dir() and not tracked_content_clean(repo):
            failures.append(f"{label} repository has tracked content changes")

    _, runtime_contract = check_source(
        candidate, runtime_standard["source_contract"], failures, "TQP-52 contract"
    )
    _, runtime_report = check_source(
        candidate, runtime_standard["source_report"], failures, "TQP-52 report"
    )
    if runtime_contract.get("schema") != runtime_standard["source_contract"]["schema"]:
        failures.append("TQP-52 contract schema mismatch")
    if runtime_contract.get("status") != "qualified":
        failures.append("TQP-52 contract is not qualified")
    if runtime_contract.get("engine_policy", {}).get("minimum_version") != "4.7":
        failures.append("TQP-52 minimum Godot version mismatch")
    if runtime_contract.get("engine_policy", {}).get("current_qualification_matrix") != ["4.7"]:
        failures.append("TQP-52 Godot qualification matrix mismatch")
    if runtime_contract.get("api", {}).get("version") != runtime_standard["required_api_version"]:
        failures.append("TQP-52 API version mismatch")
    if runtime_contract.get("profiles", {}).get("builtins") != runtime_standard["required_profiles"]:
        failures.append("TQP-52 runtime profile set mismatch")
    if runtime_contract.get("readiness", {}).get("scopes") != runtime_standard["required_readiness_scopes"]:
        failures.append("TQP-52 readiness scopes mismatch")
    if runtime_report.get("schema") != runtime_standard["source_report"]["schema"]:
        failures.append("TQP-52 report schema mismatch")
    if runtime_report.get("status") != "PASS":
        failures.append("TQP-52 report failed")
    runtime_markers = engine_markers(runtime_report)
    if list(runtime_markers) != runtime_standard["required_engines"]:
        failures.append("TQP-52 engine matrix mismatch")
    if any(not marker.startswith("WT_TERRAIN_TQP52_GODOT_PASS") for marker in runtime_markers.values()):
        failures.append("TQP-52 runtime marker mismatch")

    _, authoring_contract = check_source(
        candidate, authoring_standard["source_contract"], failures, "TQP-53 contract"
    )
    _, authoring_report = check_source(
        candidate, authoring_standard["source_report"], failures, "TQP-53 report"
    )
    if authoring_contract.get("schema") != authoring_standard["source_contract"]["schema"]:
        failures.append("TQP-53 contract schema mismatch")
    if authoring_contract.get("status") != "qualified":
        failures.append("TQP-53 contract is not qualified")
    if authoring_contract.get("engine_policy", {}).get("minimum_version") != "4.7":
        failures.append("TQP-53 minimum Godot version mismatch")
    if authoring_contract.get("engine_policy", {}).get("current_qualification_matrix") != ["4.7"]:
        failures.append("TQP-53 Godot qualification matrix mismatch")
    if authoring_contract.get("editor_workflow", {}).get("operations") != authoring_standard["required_operations"]:
        failures.append("TQP-53 authoring operation set mismatch")
    boundaries = authoring_contract.get("boundaries", {})
    for key in ["lab_runtime_dependency", "editor_code_in_exported_runtime", "procedural_field_duplication", "fallback_mesher"]:
        if boundaries.get(key) is not False:
            failures.append(f"TQP-53 boundary must remain false: {key}")
    if authoring_report.get("schema") != authoring_standard["source_report"]["schema"]:
        failures.append("TQP-53 report schema mismatch")
    if authoring_report.get("status") != "PASS":
        failures.append("TQP-53 report failed")
    if authoring_report.get("durable_inverse_claim") is not False:
        failures.append("TQP-53 makes an unsupported durable inverse claim")
    authoring_markers = engine_markers(authoring_report)
    if list(authoring_markers) != authoring_standard["required_engines"]:
        failures.append("TQP-53 engine matrix mismatch")
    if any(not marker.startswith("WT_TERRAIN_TQP53_GODOT_PASS") for marker in authoring_markers.values()):
        failures.append("TQP-53 authoring marker mismatch")

    migration_sources: dict[str, dict] = {}
    for source in migration_standard["source_contracts"]:
        _, payload = check_source(integration, source, failures, "TQP-54")
        migration_sources[source["path"]] = payload
    package_pin = migration_sources.get("TQP54_PACKAGE_PIN.json", {})
    migration_contract = migration_sources.get("TQP54_MIGRATION_CONTRACT.json", {})
    migration_report = migration_sources.get("docs/evidence/tqp54_migration_windows.json", {})
    if package_pin.get("status") != "QUALIFIED":
        failures.append("TQP-54 package pin is not qualified")
    for key in ["commit", "addon_tree", "package_digest_sha256", "files"]:
        if package_pin.get("candidate", {}).get(key) != migration_standard["candidate"].get(
            "revision" if key == "commit" else key
        ):
            failures.append(f"TQP-54 candidate package mismatch: {key}")
    for key in ["commit", "addon_tree", "package_digest_sha256", "files"]:
        if package_pin.get("authority", {}).get(key) != migration_standard["native_authority"].get(
            "revision" if key == "commit" else key
        ):
            failures.append(f"TQP-54 authority package mismatch: {key}")
    if migration_contract.get("status") != "QUALIFIED" or migration_contract.get("release_claim") is not False:
        failures.append("TQP-54 migration contract status or release boundary mismatch")
    if migration_contract.get("engine_policy", {}).get("minimum_version") != "4.7":
        failures.append("TQP-54 minimum Godot version mismatch")
    if migration_contract.get("engine_policy", {}).get("current_qualification_matrix") != ["4.7"]:
        failures.append("TQP-54 Godot qualification matrix mismatch")
    if migration_contract.get("package_policy") != "EXACT_PINNED_AUTHORITIES_NO_FALLBACKS":
        failures.append("TQP-54 package policy mismatch")
    if migration_report.get("status") != "PASS" or migration_report.get("release_claim") is not False:
        failures.append("TQP-54 retained report status or release boundary mismatch")
    import_engines = [str(item.get("engine", "")) for item in migration_report.get("project_imports", [])]
    smoke_markers = {
        str(item.get("engine", "")): str(item.get("marker", ""))
        for item in migration_report.get("runtime_smokes", [])
    }
    if import_engines != migration_standard["required_engines"] or list(smoke_markers) != migration_standard["required_engines"]:
        failures.append("TQP-54 engine matrix mismatch")
    if any(not marker.startswith("WT_TQP54_MIGRATION_GODOT_PASS") for marker in smoke_markers.values()):
        failures.append("TQP-54 migration marker mismatch")

    clean = {
        "candidate": tracked_content_clean(candidate) if candidate.is_dir() else False,
        "native_authority": tracked_content_clean(authority) if authority.is_dir() else False,
        "integration": tracked_content_clean(integration) if integration.is_dir() else False,
    }
    evidence = {
        "schema": "world_transvoxel.terrain_lab.cpu_production_first_batch_qualification.v1",
        "date": "2026-08-09",
        "status": "PASS" if not failures else "FAIL",
        "retained_complete": not failures,
        "platform": "windows-x86_64",
        "candidate": {
            "repository": runtime_standard["candidate"]["repository"],
            "revision": candidate_revision,
            "addon_tree": candidate_tree,
            "tracked_content_clean": clean["candidate"],
        },
        "native_authority": {
            "repository": runtime_standard["native_authority"]["repository"],
            "revision": authority_revision,
            "tracked_content_clean": clean["native_authority"],
        },
        "integration": {
            "repository": migration_standard["integration"]["repository"],
            "revision": integration_revision,
            "tracked_content_clean": clean["integration"],
        },
        "milestones": {
            "TQP-52": {
                "status": "PASS" if not failures else "FAIL",
                "qualification_status": "QUALIFIED_PRODUCTION_RUNTIME_CONTRACT_V1" if not failures else "UNQUALIFIED",
                "standard_id": runtime_standard["standard_id"],
                "api_version": runtime_report.get("api_version"),
                "profiles": runtime_report.get("profiles"),
                "readiness_scopes": runtime_report.get("readiness_scopes"),
                "source_contract_sha256": runtime_standard["source_contract"]["sha256"],
                "source_report_sha256": runtime_standard["source_report"]["sha256"],
                "engine_markers": runtime_markers,
            },
            "TQP-53": {
                "status": "PASS" if not failures else "FAIL",
                "qualification_status": "QUALIFIED_PRODUCTION_AUTHORING_WORKFLOW_V1" if not failures else "UNQUALIFIED",
                "standard_id": authoring_standard["standard_id"],
                "draft_undo_redo": authoring_report.get("draft_undo_redo"),
                "durable_inverse_claim": authoring_report.get("durable_inverse_claim"),
                "repro_schema": authoring_report.get("repro_schema"),
                "source_contract_sha256": authoring_standard["source_contract"]["sha256"],
                "source_report_sha256": authoring_standard["source_report"]["sha256"],
                "engine_markers": authoring_markers,
            },
            "TQP-54": {
                "status": "PASS" if not failures else "FAIL",
                "qualification_status": "QUALIFIED_DOWNSTREAM_MIGRATION_V1" if not failures else "UNQUALIFIED",
                "standard_id": migration_standard["standard_id"],
                "package_policy": migration_contract.get("package_policy"),
                "candidate_package": package_pin.get("candidate", {}),
                "authority_package": package_pin.get("authority", {}),
                "project_import_engines": import_engines,
                "runtime_smoke_markers": smoke_markers,
                "deep_gate_timeout_seconds": migration_contract.get("deep_gate_timeout_seconds"),
                "release_claim": migration_contract.get("release_claim"),
            },
        },
        "qualified_scope": [
            "TQP-52 candidate runtime API profiles readiness back-pressure and cancellation",
            "TQP-53 production authoring inspection diagnostics repro and material-payload workflow",
            "TQP-54 exact downstream package migration render collision edit persistence replay and failure behavior",
        ],
        "explicitly_unqualified_scope": [
            "TQP-55 CPU production release matrix",
            "TQP-56 long-haul certification",
            "TQP-57 standalone release",
            "non-Windows GPU and game-system claims",
        ],
        "next_milestone": "TQP-55",
        "failures": failures,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(evidence, indent="\t") + "\n", encoding="utf-8")

    if failures:
        for failure in failures:
            print("WT_TERRAIN_CPU_PRODUCTION_FIRST_BATCH_FAIL " + failure)
        return 1
    print(
        "WT_TERRAIN_CPU_PRODUCTION_FIRST_BATCH_PASS "
        f"candidate={candidate_revision} integration={integration_revision} "
        "milestones=TQP-52,TQP-53,TQP-54 next=TQP-55"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
