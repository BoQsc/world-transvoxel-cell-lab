from __future__ import annotations

import json
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

    milestones = {item["id"]: item for item in manifest["milestones"]}
    gates = manifest["gates"]
    positions: dict[str, tuple[int, int]] = {}
    active_waves: list[str] = []

    for wave_index, wave in enumerate(plan.get("waves", [])):
        wave_id = str(wave.get("id", ""))
        if wave.get("status") == "active":
            active_waves.append(wave_id)
        for step_index, step in enumerate(wave.get("steps", [])):
            for milestone_id in step:
                if milestone_id in positions:
                    failures.append(f"duplicate execution placement: {milestone_id}")
                positions[milestone_id] = (wave_index, step_index)

    missing = sorted(set(milestones) - set(positions))
    unknown = sorted(set(positions) - set(milestones))
    if missing:
        failures.append("execution plan missing: " + ",".join(missing))
    if unknown:
        failures.append("execution plan has unknown IDs: " + ",".join(unknown))

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
        f"current={plan['current_wave']} next={','.join(expected_next)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
