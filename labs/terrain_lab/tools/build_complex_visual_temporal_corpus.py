#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import Counter, defaultdict
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Retain deterministic TQP-44 visual and temporal corpus coverage."
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--standard",
        type=Path,
        default=Path(
            "addons/world_transvoxel_terrain_lab/standards/"
            "complex_visual_temporal_corpus_standard.json"
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            "labs/terrain_lab/results/"
            "complex_visual_temporal_corpus_automation_windows.json"
        ),
    )
    return parser.parse_args()


def project_path(root: Path, value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError(f"evidence path is not project-relative: {value}")
    return root / value.removeprefix("res://")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError(f"not a valid PNG: {path}")
    return struct.unpack(">II", header[16:24])


def main() -> int:
    args = parse_arguments()
    root = args.project_root.resolve()
    standard_path = args.standard if args.standard.is_absolute() else root / args.standard
    output_path = args.output if args.output.is_absolute() else root / args.output
    standard = json.loads(standard_path.read_text(encoding="utf-8"))
    contract = standard["coverage_contract"]
    failures: list[str] = []
    scale_counts: Counter[str] = Counter()
    category_counts: Counter[str] = Counter()
    subject_angles: dict[str, set[str]] = defaultdict(set)
    scenes: set[str] = set()
    still_records: list[dict] = []

    for entry in standard.get("stills", []):
        path = project_path(root, entry["path"])
        if not path.is_file():
            failures.append(f"missing still: {entry['id']}")
            continue
        try:
            width, height = png_size(path)
        except ValueError as error:
            failures.append(str(error))
            continue
        if width < 640 or height < 360:
            failures.append(f"still is below 640x360: {entry['id']}")
        scale_counts[entry["scale"]] += 1
        subject_angles[entry["subject"]].add(entry["angle"])
        scenes.add(entry["scene"])
        for category in entry.get("categories", []):
            category_counts[category] += 1
        still_records.append(
            {
                **entry,
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
                "width": width,
                "height": height,
            }
        )

    motion_records: list[dict] = []
    for entry in standard.get("motion_paths", []):
        path = project_path(root, entry["path"])
        if not path.is_file():
            failures.append(f"missing motion path: {entry['id']}")
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("status") != "PASS":
            failures.append(f"motion path failed: {entry['id']}")
        if payload.get("scene") != entry["scene"]:
            failures.append(f"motion scene changed: {entry['id']}")
        scenes.add(entry["scene"])
        motion_records.append(
            {
                **entry,
                "sha256": sha256(path),
                "schema": payload.get("schema", ""),
                "milestone": payload.get("milestone", ""),
                "capture_count": len(payload.get("captures", [])),
            }
        )

    required_scales = set(contract["required_scales"])
    if set(scale_counts) != required_scales:
        failures.append("required scale set is incomplete")
    for scale in required_scales:
        if scale_counts[scale] < int(contract["minimum_stills_per_scale"]):
            failures.append(f"too few stills at {scale} scale")
    if len(still_records) < int(contract["minimum_stills"]):
        failures.append("still count is below the declared minimum")
    if len(motion_records) < int(contract["minimum_motion_paths"]):
        failures.append("motion path count is below the declared minimum")
    if len(scenes) < int(contract["minimum_distinct_live_scenes"]):
        failures.append("live source scene count is below the declared minimum")
    multi_angle_subjects = sorted(
        subject for subject, angles in subject_angles.items() if len(angles) >= 2
    )
    if len(multi_angle_subjects) < int(contract["minimum_multi_angle_subjects"]):
        failures.append("multi-angle subject count is below the declared minimum")
    for category in contract["required_review_categories"]:
        if category_counts[category] <= 0:
            failures.append(f"review category has no evidence: {category}")

    signature_lines = [
        f"still:{record['id']}:{record['sha256']}" for record in still_records
    ] + [
        f"motion:{record['id']}:{record['sha256']}" for record in motion_records
    ]
    corpus_signature = hashlib.sha256(
        "\n".join(sorted(signature_lines)).encode("utf-8")
    ).hexdigest()
    report = {
        "schema": "world_transvoxel.terrain_lab.complex_visual_temporal_corpus_automation.v1",
        "milestone": "TQP-44",
        "status": "PASS_AUTOMATION_PENDING_HUMAN" if not failures else "FAIL",
        "standard_id": standard["standard_id"],
        "authority": standard["authority"],
        "corpus_signature": corpus_signature,
        "coverage": {
            "still_count": len(still_records),
            "motion_path_count": len(motion_records),
            "distinct_live_scene_count": len(scenes),
            "scale_counts": dict(sorted(scale_counts.items())),
            "category_counts": dict(sorted(category_counts.items())),
            "multi_angle_subjects": multi_angle_subjects,
        },
        "stills": still_records,
        "motion_paths": motion_records,
        "human_review_required": True,
        "automation_accepts_milestone": False,
        "failures": failures,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "WT_TERRAIN_LAB_TQP44_AUTOMATION_"
        + ("PASS" if not failures else "FAIL")
        + f" stills={len(still_records)} motion={len(motion_records)} "
        + f"signature={corpus_signature}"
    )
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
