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
STATE_PATH = MANIFEST_PATH.with_name("qualification_state.json")
PROGRAM_PATH = ROOT / "docs" / "terrain_lab" / "TERRAIN_QUALIFICATION_PROGRAM.md"
EXPECTED_MILESTONE_COUNT = 64


def main() -> int:
    state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    statuses: dict[str, str] = {}
    for status, milestone_ids in state["statuses"].items():
        for milestone_id in milestone_ids:
            if milestone_id in statuses:
                raise RuntimeError(f"duplicate state for {milestone_id}")
            statuses[milestone_id] = status
    if len(statuses) != EXPECTED_MILESTONE_COUNT:
        raise RuntimeError(
            "qualification state must classify "
            f"{EXPECTED_MILESTONE_COUNT} unique milestones"
        )

    manifest_source = MANIFEST_PATH.read_text(encoding="utf-8")
    manifest_pattern = re.compile(
        r'("id": "(TQP-\d+)"[^\n]*?"status": ")[^"]+'
    )
    manifest_source, manifest_count = manifest_pattern.subn(
        lambda match: f"{match.group(1)}{statuses[match.group(2)]}",
        manifest_source,
    )
    if manifest_count != EXPECTED_MILESTONE_COUNT:
        raise RuntimeError(
            f"expected {EXPECTED_MILESTONE_COUNT} manifest statuses, "
            f"updated {manifest_count}"
        )
    MANIFEST_PATH.write_text(
        manifest_source,
        encoding="utf-8",
        newline="\n",
    )

    program = PROGRAM_PATH.read_text(encoding="utf-8")
    quote = "`"
    pattern = re.compile(
        rf"(### (TQP-\d+):[^\n]+\n\n)Status: {quote}[^{quote}]+{quote}"
    )
    updated, count = pattern.subn(
        lambda match: (
            f"{match.group(1)}Status: {quote}{statuses[match.group(2)]}{quote}"
        ),
        program,
    )
    if count != EXPECTED_MILESTONE_COUNT:
        raise RuntimeError(
            f"expected {EXPECTED_MILESTONE_COUNT} Markdown statuses, updated {count}"
        )
    PROGRAM_PATH.write_text(updated, encoding="utf-8", newline="\n")
    print(
        "TQP_STATUS_SYNC_PASS "
        f"manifest={manifest_count} markdown={count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
