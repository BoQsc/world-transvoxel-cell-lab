from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


CAPTURE_FAILURE_MARKERS = (
    "SCRIPT ERROR:",
    "WT_CELL_LAB_VISUAL_CAPTURE_FAIL",
)
DEFAULT_CANDIDATE_DIRECTORY = Path(".godot/cell_lab_visual_candidate")
DEFAULT_CAPTURE_LOG = Path(".godot/cell_lab_visual_capture.log")
DEFAULT_REPORT = Path(".godot/cell_lab_visual_diff.json")
GODOT_CANDIDATES = (
    "Godot_v4.7.1-stable_win64.exe",
    "godot.exe",
    "godot4.exe",
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Capture fresh Forward+ Cell Lab visuals and compare them with "
            "the committed standards."
        )
    )
    parser.add_argument(
        "--godot",
        default=os.environ.get("GODOT_BIN"),
        help="Godot executable path or command name; defaults to GODOT_BIN/PATH.",
    )
    parser.add_argument(
        "--candidate-dir",
        type=Path,
        default=DEFAULT_CANDIDATE_DIRECTORY,
    )
    parser.add_argument(
        "--capture-log",
        type=Path,
        default=DEFAULT_CAPTURE_LOG,
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=DEFAULT_REPORT,
    )
    parser.add_argument("--timeout-seconds", type=int, default=300)
    args = parser.parse_args()

    if os.name != "nt":
        parser.error("authoritative visual capture currently requires Windows")
    if args.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")

    project_root = Path(__file__).resolve().parents[3]
    evidence_root = (project_root / ".godot").resolve()
    candidate_directory = _resolve_evidence_path(
        project_root,
        evidence_root,
        args.candidate_dir,
        "candidate directory",
    )
    capture_log = _resolve_evidence_path(
        project_root,
        evidence_root,
        args.capture_log,
        "capture log",
    )
    report = _resolve_evidence_path(
        project_root,
        evidence_root,
        args.report,
        "diff report",
    )
    godot = _find_godot(args.godot)
    visual_manifest = (
        project_root
        / "addons/world_transvoxel_cell_lab/standards/visual_manifest.json"
    )
    expected_visual_count = len(
        json.loads(visual_manifest.read_text(encoding="utf-8"))["visuals"]
    )
    capture_pass_marker = (
        f"WT_CELL_LAB_VISUAL_CAPTURE_PASS count={expected_visual_count}"
    )

    if candidate_directory.exists():
        shutil.rmtree(candidate_directory)
    candidate_directory.mkdir(parents=True)
    capture_log.parent.mkdir(parents=True, exist_ok=True)
    capture_log.unlink(missing_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.unlink(missing_ok=True)

    candidate_resource_path = (
        "res://" + candidate_directory.relative_to(project_root).as_posix()
    )
    command = [
        str(godot),
        "--audio-driver",
        "Dummy",
        "--display-driver",
        "windows",
        "--rendering-method",
        "forward_plus",
        "--rendering-driver",
        "d3d12",
        "--resolution",
        "1152x648",
        "--disable-vsync",
        "--path",
        str(project_root),
        "--log-file",
        str(capture_log),
        "--script",
        "res://labs/cell_lab/tools/capture_standard_visuals.gd",
        "--",
        f"output={candidate_resource_path}",
    ]
    print("Running authoritative Forward+/D3D12 visual capture:")
    print(subprocess.list2cmdline(command), flush=True)
    try:
        capture = subprocess.run(
            command,
            cwd=project_root,
            check=False,
            timeout=args.timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        print(
            f"Visual capture exceeded {args.timeout_seconds} seconds.",
            file=sys.stderr,
        )
        return 1
    if capture.returncode != 0:
        print(
            f"Visual capture exited with code {capture.returncode}.",
            file=sys.stderr,
        )
        _print_capture_log(capture_log)
        return 1
    if not capture_log.exists():
        print("Visual capture log was not created.", file=sys.stderr)
        return 1
    capture_output = capture_log.read_text(
        encoding="utf-8",
        errors="replace",
    )
    if any(marker in capture_output for marker in CAPTURE_FAILURE_MARKERS):
        print("Visual capture log contains a failure marker.", file=sys.stderr)
        _print_capture_log(capture_log)
        return 1
    if capture_pass_marker not in capture_output:
        print("Visual capture pass marker is missing.", file=sys.stderr)
        _print_capture_log(capture_log)
        return 1

    comparator = project_root / "labs/cell_lab/tools/compare_visual_standards.py"
    comparison = subprocess.run(
        [
            sys.executable,
            str(comparator),
            "--candidate-dir",
            str(candidate_directory),
            "--output",
            str(report),
        ],
        cwd=project_root,
        check=False,
    )
    if comparison.returncode != 0:
        return comparison.returncode
    print(
        "WT_CELL_LAB_FRESH_VISUAL_VALIDATION_PASS "
        f"candidate_dir={candidate_directory} report={report}"
    )
    return 0


def _resolve_evidence_path(
    project_root: Path,
    evidence_root: Path,
    value: Path,
    label: str,
) -> Path:
    resolved = (
        value.resolve()
        if value.is_absolute()
        else (project_root / value).resolve()
    )
    if resolved == evidence_root:
        raise SystemExit(f"{label} must be below {evidence_root}")
    try:
        resolved.relative_to(evidence_root)
    except ValueError as error:
        raise SystemExit(f"{label} must be below {evidence_root}") from error
    return resolved


def _find_godot(configured: str | None) -> Path:
    candidates = (configured,) if configured else GODOT_CANDIDATES
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if path.is_file():
            return path.resolve()
        discovered = shutil.which(candidate)
        if discovered:
            return Path(discovered).resolve()
    raise SystemExit(
        "Godot executable was not found; pass --godot or set GODOT_BIN."
    )


def _print_capture_log(capture_log: Path) -> None:
    if capture_log.exists():
        print(capture_log.read_text(encoding="utf-8", errors="replace"))


if __name__ == "__main__":
    raise SystemExit(main())
