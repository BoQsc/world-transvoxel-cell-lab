#!/usr/bin/env python3
"""Build retained TQP-25 still, motion, video, and machine evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
STANDARD_PATH = (
    REPO_ROOT
    / "addons/world_transvoxel_terrain_lab/standards/visual_quality_corpus_standard.json"
)
REPORT_PATH = (
    REPO_ROOT
    / "labs/terrain_lab/results/visual_quality_corpus_reference_windows.json"
)
FRAME_ROOT = REPO_ROOT / ".godot/tqp25_frames"
CAPTURE_SCRIPT = "res://labs/terrain_lab/tools/capture_visual_quality_corpus.gd"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Godot editor executable")
    parser.add_argument("--keep-frames", action="store_true", help="Retain intermediate PNG frames")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_checked(command: list[str], label: str) -> subprocess.CompletedProcess[str]:
    creationflags = 0
    if sys.platform == "win32":
        creationflags = getattr(subprocess, "HIGH_PRIORITY_CLASS", 0)
    print(f"[{label}] {' '.join(command)}", flush=True)
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        creationflags=creationflags,
        check=False,
    )
    print(completed.stdout, end="")
    if completed.returncode != 0:
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}")
    return completed


def encode_video(
    ffmpeg: str,
    ffprobe: str,
    fixture_id: str,
    fps: int,
    expected_frames: int,
    width: int,
    height: int,
    codec: str,
    pixel_format: str,
) -> dict[str, object]:
    frame_pattern = FRAME_ROOT / fixture_id / "%03d.png"
    output = REPO_ROOT / f"labs/terrain_lab/results/visual_quality_{fixture_id}_motion.mp4"
    run_checked(
        [
            ffmpeg,
            "-y",
            "-loglevel",
            "error",
            "-framerate",
            str(fps),
            "-i",
            str(frame_pattern),
            "-c:v",
            "libx264",
            "-crf",
            "18",
            "-preset",
            "medium",
            "-pix_fmt",
            pixel_format,
            "-movflags",
            "+faststart",
            str(output),
        ],
        f"encode {fixture_id}",
    )
    probe = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-count_frames",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=codec_name,pix_fmt,width,height,avg_frame_rate,nb_read_frames,duration",
            "-of",
            "json",
            str(output),
        ],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    metadata = json.loads(probe.stdout)["streams"][0]
    actual_frames = int(metadata.get("nb_read_frames", 0))
    actual_width = int(metadata.get("width", 0))
    actual_height = int(metadata.get("height", 0))
    actual_codec = str(metadata.get("codec_name", ""))
    actual_pixel_format = str(metadata.get("pix_fmt", ""))
    failures: list[str] = []
    if actual_frames != expected_frames:
        failures.append(f"video frame count {actual_frames} != {expected_frames}")
    if (actual_width, actual_height) != (width, height):
        failures.append(
            f"video dimensions {actual_width}x{actual_height} != {width}x{height}"
        )
    if actual_codec != codec:
        failures.append(f"video codec {actual_codec} != {codec}")
    if actual_pixel_format != pixel_format:
        failures.append(f"video pixel format {actual_pixel_format} != {pixel_format}")
    return {
        "path": f"res://labs/terrain_lab/results/{output.name}",
        "status": "PASS" if not failures else "FAIL",
        "sha256": sha256(output),
        "codec": actual_codec,
        "pixel_format": actual_pixel_format,
        "width": actual_width,
        "height": actual_height,
        "frame_count": actual_frames,
        "average_frame_rate": str(metadata.get("avg_frame_rate", "")),
        "duration_seconds": float(metadata.get("duration", 0.0)),
        "failures": failures,
    }


def main() -> int:
    args = parse_args()
    godot = args.godot.resolve()
    if not godot.is_file():
        raise FileNotFoundError(f"Godot executable not found: {godot}")
    ffmpeg = shutil.which("ffmpeg")
    ffprobe = shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise RuntimeError("ffmpeg and ffprobe are required for retained TQP-25 videos")
    standard = json.loads(STANDARD_PATH.read_text(encoding="utf-8"))
    contract = standard["capture_contract"]
    shutil.rmtree(FRAME_ROOT, ignore_errors=True)
    run_checked(
        [
            str(godot),
            "--path",
            str(REPO_ROOT),
            "--resolution",
            f"{contract['width']}x{contract['height']}",
            "--rendering-method",
            "forward_plus",
            "--script",
            CAPTURE_SCRIPT,
        ],
        "capture corpus",
    )
    report = json.loads(REPORT_PATH.read_text(encoding="utf-8"))
    failures = list(report.get("failures", []))
    records = {record["id"]: record for record in report.get("fixtures", [])}
    for fixture in standard["fixtures"]:
        fixture_id = fixture["id"]
        record = records.get(fixture_id)
        if record is None:
            failures.append(f"missing capture record for {fixture_id}")
            continue
        video = encode_video(
            ffmpeg,
            ffprobe,
            fixture_id,
            int(contract["motion_fps"]),
            int(contract["motion_frame_count"]),
            int(contract["width"]),
            int(contract["height"]),
            str(contract["video_codec"]),
            str(contract["video_pixel_format"]),
        )
        record["video"] = video
        failures.extend(f"{fixture_id}: {message}" for message in video["failures"])
    report["status"] = "PASS" if not failures else "FAIL"
    report["failures"] = failures
    REPORT_PATH.write_text(json.dumps(report, indent="\t") + "\n", encoding="utf-8")
    if not args.keep_frames and not failures:
        shutil.rmtree(FRAME_ROOT)
    print(
        json.dumps(
            {
                "status": report["status"],
                "fixture_count": len(report.get("fixtures", [])),
                "formal_human_review": report.get("formal_human_review"),
                "failures": failures,
            },
            indent=2,
        )
    )
    return 0 if not failures else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # Evidence generation must fail closed with context.
        print(f"TQP-25 corpus build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
