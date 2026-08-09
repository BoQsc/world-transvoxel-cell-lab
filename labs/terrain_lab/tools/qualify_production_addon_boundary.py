from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REPOSITORY_ROOT = ROOT.parent
STANDARD_PATH = (
    ROOT
    / "addons"
    / "world_transvoxel_terrain_lab"
    / "standards"
    / "production_addon_boundary_standard.json"
)
OUTPUT_PATH = (
    ROOT
    / "labs"
    / "terrain_lab"
    / "results"
    / "production_addon_boundary_reference_windows.json"
)


def git(repo: Path, *args: str) -> str:
    command = [
        "git",
        "-c",
        f"safe.directory={repo.as_posix()}",
        *args,
    ]
    return subprocess.check_output(command, cwd=repo, text=True).strip()


def run_validator(script: Path, repo: Path) -> dict[str, str | int]:
    completed = subprocess.run(
        [sys.executable, "-B", str(script)],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    output = "\n".join(part for part in [completed.stdout, completed.stderr] if part).strip()
    marker = ""
    for line in reversed(output.splitlines()):
        if line.startswith("WT_TERRAIN_"):
            marker = line
            break
    return {
        "script": script.relative_to(repo).as_posix(),
        "return_code": completed.returncode,
        "marker": marker,
    }


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    standard = load_json(STANDARD_PATH)
    candidate_spec = standard["candidate"]
    upstream_spec = standard["native_authority"]
    candidate = REPOSITORY_ROOT / candidate_spec["repository"]
    upstream = REPOSITORY_ROOT / upstream_spec["repository"]
    failures: list[str] = []

    if not candidate.is_dir():
        failures.append(f"candidate repository missing: {candidate}")
    if not upstream.is_dir():
        failures.append(f"native authority repository missing: {upstream}")

    candidate_revision = git(candidate, "rev-parse", "HEAD") if candidate.is_dir() else ""
    upstream_revision = git(upstream, "rev-parse", "HEAD") if upstream.is_dir() else ""
    if candidate_revision != candidate_spec["revision"]:
        failures.append("candidate revision does not match the TQP-51 pin")
    if upstream_revision != upstream_spec["revision"]:
        failures.append("native authority revision does not match the TQP-51 pin")

    candidate_dirty = git(candidate, "status", "--porcelain", "--untracked-files=no") if candidate.is_dir() else ""
    upstream_dirty = git(upstream, "status", "--porcelain", "--untracked-files=no") if upstream.is_dir() else ""
    if candidate_dirty:
        failures.append("candidate repository has tracked worktree changes")
    if upstream_dirty:
        failures.append("native authority repository has tracked worktree changes")

    contract_path = candidate / candidate_spec["addon_root"] / "BOUNDARY_CONTRACT.json"
    contract = load_json(contract_path) if contract_path.is_file() else {}
    if not contract:
        failures.append("candidate boundary contract is missing or invalid")
    if contract.get("schema") != candidate_spec["boundary_contract_schema"]:
        failures.append("candidate boundary contract schema mismatch")
    if contract.get("candidate_id") != candidate_spec["candidate_id"]:
        failures.append("candidate boundary identity mismatch")
    if contract.get("status") != "CANDIDATE_BOUNDARY_FROZEN":
        failures.append("candidate boundary is not frozen")
    if contract.get("release_claim") is not False:
        failures.append("TQP-51 candidate makes a release claim")
    dependency = contract.get("dependency", {})
    if dependency.get("required_revision") != upstream_spec["revision"]:
        failures.append("candidate contract does not pin the retained native authority")
    if dependency.get("vendored") is not False or dependency.get("fallback_mesher") is not False:
        failures.append("candidate contract permits vendoring or a fallback mesher")
    if contract.get("failure_policy", {}).get("silent_fallback") is not False:
        failures.append("candidate contract permits silent fallback")
    for section in standard["required_contract_sections"]:
        if not contract.get(section):
            failures.append(f"candidate boundary contract section missing: {section}")

    contract_digest = sha256(contract_path) if contract_path.is_file() else ""
    if contract_digest != candidate_spec["boundary_contract_sha256"]:
        failures.append("candidate boundary contract digest mismatch")
    addon_tree = (
        git(candidate, "rev-parse", f"HEAD:{candidate_spec['addon_root']}")
        if candidate.is_dir()
        else ""
    )
    if addon_tree != candidate_spec["addon_tree"]:
        failures.append("candidate addon tree does not match the TQP-51 pin")

    validator_results = []
    if candidate.is_dir():
        for script in sorted((candidate / "tools").glob("validate_*.py")):
            result = run_validator(script, candidate)
            validator_results.append(result)
            if result["return_code"] != 0 or not str(result["marker"]).startswith("WT_TERRAIN_"):
                failures.append(f"candidate validator failed: {result['script']}")
    if len(validator_results) != standard["required_static_validator_count"]:
        failures.append("candidate static validator count changed")

    runtime_reports: dict[str, dict] = {}
    for report_id, relative in standard["required_runtime_regression_reports"].items():
        report_path = candidate / relative
        if not report_path.is_file():
            failures.append(f"runtime regression report missing: {report_id}")
            continue
        report = load_json(report_path)
        runtime_reports[report_id] = {
            "source": relative,
            "sha256": sha256(report_path),
            "validators": int(report.get("validators", 0)),
            "smokes": int(report.get("smokes", 0)),
            "decision": str(report.get("decision", "")),
            "step_count": len(report.get("steps", [])),
        }
    expected_runtime = {
        "a4": ("a4_complete", 9, 6),
        "a5": ("a5_complete", 7, 4),
        "a6": ("approve_validation_game_repository", 2, 0),
    }
    for report_id, (decision, validators, smokes) in expected_runtime.items():
        report = runtime_reports.get(report_id, {})
        if report.get("decision") != decision:
            failures.append(f"runtime regression decision mismatch: {report_id}")
        if report.get("validators") != validators or report.get("smokes") != smokes:
            failures.append(f"runtime regression coverage mismatch: {report_id}")

    evidence = {
        "schema": "world_transvoxel.terrain_lab.production_addon_boundary_qualification.v1",
        "milestone": "TQP-51",
        "status": "PASS" if not failures else "FAIL",
        "qualification_status": "QUALIFIED_CANDIDATE_PRODUCTION_ADDON_BOUNDARY_V1" if not failures else "UNQUALIFIED",
        "retained_complete": not failures,
        "candidate": {
            "repository": candidate_spec["repository"],
            "revision": candidate_revision,
            "tracked_worktree_clean": not bool(candidate_dirty),
            "addon_root": candidate_spec["addon_root"],
            "addon_tree": addon_tree,
            "candidate_id": contract.get("candidate_id", ""),
            "boundary_contract_sha256": contract_digest,
            "boundary_status": contract.get("status", ""),
            "fallback_mesher": dependency.get("fallback_mesher"),
            "silent_fallback": contract.get("failure_policy", {}).get("silent_fallback"),
        },
        "native_authority": {
            "repository": upstream_spec["repository"],
            "revision": upstream_revision,
            "tracked_worktree_clean": not bool(upstream_dirty),
        },
        "static_validation": {
            "status": "PASS" if all(item["return_code"] == 0 for item in validator_results) else "FAIL",
            "validator_count": len(validator_results),
            "validators": validator_results,
        },
        "runtime_regression": runtime_reports,
        "qualified_scope": standard["qualified_scope"],
        "unqualified_scope": standard["unqualified_scope"],
        "next_milestone": "TQP-52",
        "failures": failures,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(evidence, indent="\t") + "\n", encoding="utf-8")

    if failures:
        for failure in failures:
            print("WT_TERRAIN_TQP51_QUALIFICATION_FAIL " + failure)
        return 1
    print(
        "WT_TERRAIN_TQP51_QUALIFICATION_PASS "
        f"candidate={candidate_revision} upstream={upstream_revision} "
        f"validators={len(validator_results)} next=TQP-52"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
