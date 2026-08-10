from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = (
    ROOT
    / "addons"
    / "world_transvoxel_terrain_lab"
    / "standards"
    / "program_manifest.json"
)


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    plan_path = ROOT / manifest["execution_plan"].removeprefix("res://")
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    failures: list[str] = []

    if plan.get("schema") != "world_transvoxel.terrain_lab.execution_plan.v1":
        failures.append("execution plan schema mismatch")
    if plan.get("program_revision") != manifest.get("program_revision"):
        failures.append("execution plan program revision mismatch")
    if plan.get("human_authority") != manifest.get("contract_document"):
        failures.append("execution plan human authority differs from the TQP")

    milestones = {item["id"]: item for item in manifest["milestones"]}
    expected_ids = [f"TQP-{number:02d}" for number in range(1, 72)]
    manifest_order = [item["id"] for item in manifest["milestones"]]
    if manifest_order != expected_ids:
        failures.append("program manifest is not in TQP-01 through TQP-71 order")
    gates = manifest["gates"]
    positions: dict[str, tuple[int, int]] = {}
    execution_order: list[str] = []
    active_waves: list[str] = []

    for wave_index, wave in enumerate(plan.get("waves", [])):
        wave_id = str(wave.get("id", ""))
        if wave.get("status") == "active":
            active_waves.append(wave_id)
        for step_index, step in enumerate(wave.get("steps", [])):
            for milestone_id in step:
                execution_order.append(milestone_id)
                if milestone_id in positions:
                    failures.append(f"duplicate execution placement: {milestone_id}")
                positions[milestone_id] = (wave_index, step_index)

    missing = sorted(set(milestones) - set(positions))
    unknown = sorted(set(positions) - set(milestones))
    if missing:
        failures.append("execution plan missing: " + ",".join(missing))
    if unknown:
        failures.append("execution plan has unknown IDs: " + ",".join(unknown))
    if execution_order != expected_ids:
        failures.append("execution plan is not in TQP-01 through TQP-71 order")

    contract_path = ROOT / manifest["contract_document"].removeprefix("res://")
    contract_source = contract_path.read_text(encoding="utf-8")
    contract_headings = re.findall(
        r"^### (TQP-[0-9]{2}): (.+)$",
        contract_source,
        re.MULTILINE,
    )
    contract_order = [milestone_id for milestone_id, _title in contract_headings]
    if contract_order != expected_ids:
        failures.append("TQP document is not in TQP-01 through TQP-71 order")
    for milestone, heading in zip(manifest["milestones"], contract_headings):
        milestone_id, heading_title = heading
        if milestone["id"] != milestone_id or milestone["title"] != heading_title:
            failures.append(f"TQP heading differs from manifest: {milestone['id']}")
        anchor_text = re.sub(
            r"[^a-z0-9 _-]",
            "",
            f"{milestone_id} {heading_title}".lower(),
        )
        expected_anchor = "#" + re.sub(r" +", "-", anchor_text)
        if milestone.get("contract_ref") != expected_anchor:
            failures.append(f"TQP anchor differs from manifest: {milestone_id}")

    for milestone_id, milestone in milestones.items():
        if milestone_id not in positions:
            continue
        for dependency in milestone.get("depends_on", []):
            expanded = gates.get(dependency, [dependency])
            for dependency_id in expanded:
                if dependency_id not in positions:
                    failures.append(
                        f"{milestone_id} dependency is unplaced: {dependency_id}"
                    )
                elif positions[dependency_id] >= positions[milestone_id]:
                    failures.append(
                        f"backward execution dependency: {milestone_id} requires "
                        f"{dependency_id}"
                    )

    if active_waves != [plan.get("current_wave")]:
        failures.append("execution plan must have exactly one matching active wave")

    qualified = {"qualified", "production"}
    for wave in plan.get("waves", []):
        if wave.get("status") != "completed":
            continue
        for step in wave.get("steps", []):
            for milestone_id in step:
                if milestones.get(milestone_id, {}).get("status") not in qualified:
                    failures.append(
                        f"completed wave contains unqualified milestone: {milestone_id}"
                    )

    current = next(
        (
            wave
            for wave in plan.get("waves", [])
            if wave.get("id") == plan.get("current_wave")
        ),
        {},
    )

    cpu_finalization_path = ROOT / manifest["cpu_finalization_evidence"].removeprefix(
        "res://"
    )
    cpu_finalization = json.loads(cpu_finalization_path.read_text(encoding="utf-8"))
    cpu_eligible = (
        cpu_finalization.get("status") == "PASS"
        and cpu_finalization.get("retained_complete") is True
        and cpu_finalization.get("tqp58_eligible") is True
        and cpu_finalization.get("consistency_failures") == []
    )
    cpu_production_closure_path = ROOT / manifest[
        "cpu_production_closure_evidence"
    ].removeprefix("res://")
    cpu_production_closure = json.loads(
        cpu_production_closure_path.read_text(encoding="utf-8")
    )
    production_eligible = (
        cpu_production_closure.get("status") == "PASS"
        and cpu_production_closure.get("retained_complete") is True
        and cpu_production_closure.get("tqp58_eligible") is True
        and cpu_production_closure.get("consistency_failures") == []
        and cpu_production_closure.get("logical_cpu_affinity") == [0, 1, 2]
        and cpu_production_closure.get("native_build_jobs") == 3
        and [
            (subgate.get("id"), subgate.get("status"))
            for subgate in cpu_production_closure.get("subgates", [])
        ]
        == [(f"TQP-R{number:02d}", "PASS") for number in range(1, 7)]
    )
    required_preconditions = [
        "CPU_FINALIZATION_PRECONDITION",
        "CPU_PRODUCTION_CLOSURE_PRECONDITION",
    ]
    if current.get("entry_condition") != "CPU_FINALIZATION_PRECONDITION":
        failures.append("active GPU wave is missing its primary CPU entry condition")
    if current.get("entry_conditions") != required_preconditions:
        failures.append("active GPU wave CPU entry conditions are missing or out of order")
    if milestones.get("TQP-58", {}).get("entry_conditions") != required_preconditions:
        failures.append("TQP-58 CPU entry conditions are missing or out of order")

    if not cpu_eligible:
        if not str(plan.get("recommended_action", "")).startswith("Complete CPU-C1"):
            failures.append("execution plan does not direct work to CPU-C1 first")
        if plan.get("recommended_precondition_steps") != ["CPU-C1", "CPU-C2", "CPU-C3"]:
            failures.append("CPU finalization precondition steps are missing or out of order")
        if milestones.get("TQP-58", {}).get("status") != "blocked":
            failures.append("TQP-58 must remain blocked until CPU finalization passes")
    elif not production_eligible:
        if not str(plan.get("recommended_action", "")).startswith("Complete TQP-R01"):
            failures.append("execution plan does not direct work to TQP-R01 first")
        if plan.get("recommended_precondition_steps") != [
            "TQP-R01",
            "TQP-R02",
            "TQP-R03",
            "TQP-R04",
            "TQP-R05",
            "TQP-R06",
        ]:
            failures.append("CPU production closure steps are missing or out of order")
        if milestones.get("TQP-58", {}).get("status") != "blocked":
            failures.append("TQP-58 must remain blocked until CPU production closure passes")
    else:
        if plan.get("completed_preconditions") != required_preconditions:
            failures.append("qualified CPU preconditions are missing or out of order")
        if plan.get("recommended_precondition_steps") != []:
            failures.append("completed CPU precondition steps remain recommended")
        if not str(plan.get("recommended_action", "")).startswith("Execute TQP-58"):
            failures.append("execution plan does not direct work to eligible TQP-58")
        if milestones.get("TQP-58", {}).get("status") != "specified":
            failures.append("eligible TQP-58 must be specified, not qualified or blocked")
    expected_next: list[str] = []
    for step in current.get("steps", []):
        incomplete = [
            milestone_id
            for milestone_id in step
            if milestones.get(milestone_id, {}).get("status") not in qualified
        ]
        if incomplete:
            expected_next = incomplete
            break
    if plan.get("recommended_next") != expected_next:
        failures.append(
            "recommended_next differs from the active wave's first incomplete step"
        )

    if failures:
        for failure in failures:
            print("WT_TQP_EXECUTION_PLAN_FAIL " + failure)
        return 1

    print(
        "WT_TQP_EXECUTION_PLAN_PASS "
        f"milestones={len(milestones)} waves={len(plan['waves'])} "
        f"current={plan['current_wave']} "
        f"action={','.join(plan.get('recommended_next', expected_next))} "
        f"next_numbered={','.join(expected_next)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
