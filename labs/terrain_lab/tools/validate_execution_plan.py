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
    cpu_human_trace_path = ROOT / manifest[
        "cpu_human_baseline_trace_evidence"
    ].removeprefix("res://")
    cpu_human_trace = json.loads(cpu_human_trace_path.read_text(encoding="utf-8"))
    cpu_human_steps = [
        (step.get("id"), step.get("status"))
        for step in cpu_human_trace.get("steps", [])
    ]
    cpu_human_baseline_retained = (
        cpu_human_trace.get("logical_cpu_affinity") == [0, 1, 2]
        and cpu_human_steps[:1] == [("CPU-B1", "PASS")]
        and cpu_human_trace.get("steps", [{}])[0].get("evidence_commit")
        == "32adc3164b4bbd7b2b13b0fccbfefadd980231d1"
        and cpu_human_trace.get("steps", [{}])[0].get("measurement_commit")
        == "413eaa5c9c612bd0ee3bf939b233723d9d2a8080"
        and cpu_human_trace.get("steps", [{}])[0].get("authority_commit")
        == "f30818b9ce0f0b3f9ddb75726db5522d97167404"
        and cpu_human_trace.get("steps", [{}])[0].get("evidence_sha256")
        == "5f2552537503237572268565f98fd2f7683a6e2ef8097497a1867d0c51fdc34f"
        and cpu_human_trace.get("baseline", {}).get("runs") == 3
        and cpu_human_trace.get("baseline", {}).get(
            "relocation_to_exact_visual_ready_ms"
        )
        == [14532.785, 316.719, 13206.199]
    )
    cpu_b2 = cpu_human_trace.get("steps", [{}, {}])[1]
    cpu_b2_retained = (
        len(cpu_human_steps) == 3
        and cpu_human_steps[:2] == [("CPU-B1", "PASS"), ("CPU-B2", "PASS")]
        and cpu_b2.get("evidence_commit")
        == "0950e3dfece191b25eb8094fbf6c1217ffe0207f"
        and cpu_b2.get("measurement_commit")
        == "5c07dc6ea7580533fac79e185f0e20d2659e8af2"
        and cpu_b2.get("authority_commit")
        == "f7a583d9e22ae39bc4d9e99178da3f782a2abe61"
        and cpu_b2.get("evidence_sha256")
        == "d5cced62da4a89728027d16d65a2ffb6732fa2f259abbfc857b05bdf4d86ea76"
        and cpu_b2.get("causal_slice_sha256")
        == "803f0af99a4440f52de655597e43b536b27da5c14553981f18e7da0e97a83c66"
        and cpu_human_trace.get("cpu_b2", {}).get("status") == "PASS"
        and cpu_human_trace.get("cpu_b2", {}).get(
            "visibility_wait_after_last_sink_ms"
        ) == 12932.0035
        and cpu_human_trace.get("cpu_b2", {}).get(
            "transition_work", {}
        ).get("classification") == "EXPLICIT_TRANSITION_MESH_CHAIN_CONFIRMED"
        and cpu_human_trace.get("cpu_b2", {}).get(
            "transition_work", {}
        ).get("unmatched_completion_consumptions") == 0
        and cpu_human_trace.get("cpu_b2", {}).get("observer_overhead", {}).get(
            "performance_baseline_allowed"
        ) is False
    )
    cpu_b3 = cpu_human_trace.get("steps", [{}, {}, {}])[2]
    cpu_b3_retained = (
        len(cpu_human_steps) == 3
        and cpu_human_steps[2] == ("CPU-B3", "IN_PROGRESS")
        and cpu_b3.get("evidence_commit")
        == "6bd1e7f11229e25fd5965856e0b3b38b80335554"
        and cpu_b3.get("candidate_commit")
        == "eb8a69c19801bb3e52837e3c565159827b560d3d"
        and cpu_b3.get("authority_commit")
        == "a8bba838a8860ba30bdb79887ad66ba17028ad18"
        and cpu_b3.get("evidence_sha256")
        == "c61d0a415b29d737667ab8d980185f96803f2524f1e0432cde3df4e9d7fe24ae"
        and cpu_b3.get("result")
        == "CORRECTNESS_HOTFIX_RETAINED_PERFORMANCE_TARGET_MISS"
        and cpu_b3.get("human_review_commit")
        == "bf59a98f51ada8cd9ef6fe1a71100984b87046c0"
        and cpu_b3.get("human_review_sha256")
        == "81142cdc1ac5f3ffeaccd5fc8e6d2ca6bf5e984433ed2eae3affcfc86f55da93"
        and cpu_b3.get("human_review_status")
        == "ACCEPTED_WITH_KNOWN_LIMITATIONS"
        and cpu_b3.get("remaining")
        == ["INDEPENDENT_CPU_EXHAUSTION_REVIEW"]
        and cpu_human_trace.get("cpu_b3", {}).get("status") == "IN_PROGRESS"
        and cpu_human_trace.get("cpu_b3", {}).get("trace_off_medians", {}).get(
            "relocation_to_visual_ready_ms"
        ) == 3822.632
        and cpu_human_trace.get("cpu_b3", {}).get(
            "rejected_viewer_region_experiment", {}
        ).get("reverted") is True
        and cpu_human_trace.get("cpu_b3", {}).get("human_review", {}).get("status")
        == "ACCEPTED_WITH_KNOWN_LIMITATIONS"
        and cpu_human_trace.get("cpu_b3", {}).get("human_review", {}).get(
            "release_blocking_limitations"
        )
        == [
            "TEMPORARY_LOD_SEE_THROUGH_SLICE",
            "RESIDUAL_FLIGHT_RESPONSIVENESS",
            "RELOCATION_FIRST_EDIT_DELAY",
        ]
    )
    cpu_human_eligible = (
        cpu_human_trace.get("status") == "PASS"
        and cpu_human_trace.get("retained_complete") is True
        and cpu_human_trace.get("tqp58_eligible") is True
        and cpu_human_trace.get("consistency_failures") == []
        and cpu_human_steps
        == [("CPU-B1", "PASS"), ("CPU-B2", "PASS"), ("CPU-B3", "PASS")]
    )
    required_preconditions = [
        "CPU_FINALIZATION_PRECONDITION",
        "CPU_PRODUCTION_CLOSURE_PRECONDITION",
        "CPU_HUMAN_BASELINE_TRACE_PRECONDITION",
    ]
    if current.get("entry_condition") != "CPU_FINALIZATION_PRECONDITION":
        failures.append("active GPU wave is missing its primary CPU entry condition")
    if current.get("entry_conditions") != required_preconditions:
        failures.append("active GPU wave entry conditions are missing or out of order")
    if milestones.get("TQP-58", {}).get("entry_conditions") != required_preconditions:
        failures.append("TQP-58 entry conditions are missing or out of order")

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
    elif not cpu_human_baseline_retained:
        if not str(plan.get("recommended_action", "")).startswith("Complete CPU-B1"):
            failures.append("execution plan does not direct work to CPU-B1 first")
        if plan.get("recommended_precondition_steps") != ["CPU-B1", "CPU-B2", "CPU-B3"]:
            failures.append("CPU human baseline/trace steps are missing or out of order")
        if plan.get("completed_precondition_steps") != []:
            failures.append("unretained CPU human steps are marked complete")
        if milestones.get("TQP-58", {}).get("status") != "blocked":
            failures.append("TQP-58 must remain blocked until CPU-B1 is retained")
    elif not cpu_human_eligible:
        if plan.get("completed_preconditions") != [
            "CPU_FINALIZATION_PRECONDITION",
            "CPU_PRODUCTION_CLOSURE_PRECONDITION",
        ]:
            failures.append("completed preconditions are missing or out of order")
        if cpu_b2_retained:
            if not cpu_b3_retained:
                failures.append("retained CPU-B3 candidate evidence is missing or inconsistent")
            if plan.get("completed_precondition_steps") != ["CPU-B1", "CPU-B2"]:
                failures.append("completed CPU-B1 and CPU-B2 steps are missing or out of order")
            if plan.get("recommended_precondition_steps") != ["CPU-B3"]:
                failures.append("CPU-B3 is not the sole next precondition step")
            if not str(plan.get("recommended_action", "")).startswith("Complete CPU-B3"):
                failures.append("execution plan does not direct work to CPU-B3 next")
        else:
            if plan.get("completed_precondition_steps") != ["CPU-B1"]:
                failures.append("completed CPU human steps are missing or out of order")
            if plan.get("recommended_precondition_steps") != ["CPU-B2", "CPU-B3"]:
                failures.append("CPU-B2 and CPU-B3 are missing or out of order")
            if not str(plan.get("recommended_action", "")).startswith("Complete CPU-B2"):
                failures.append("execution plan does not direct work to CPU-B2 next")
        if milestones.get("TQP-58", {}).get("status") != "blocked":
            failures.append("TQP-58 must remain blocked until CPU-B2 and CPU-B3 pass")
    else:
        if plan.get("completed_preconditions") != required_preconditions:
            failures.append("qualified preconditions are missing or out of order")
        if plan.get("completed_precondition_steps") != ["CPU-B1", "CPU-B2", "CPU-B3"]:
            failures.append("qualified CPU human steps are missing or out of order")
        if plan.get("recommended_precondition_steps") != []:
            failures.append("completed precondition steps remain recommended")
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
    if not (cpu_eligible and production_eligible and cpu_human_eligible):
        expected_next = []
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
