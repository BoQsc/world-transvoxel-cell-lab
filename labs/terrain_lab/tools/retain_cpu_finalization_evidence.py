from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SOURCE = ROOT.parent / "world-transvoxel-terrain" / "artifacts" / "cpu_finalization"
DESTINATION = ROOT / "labs" / "terrain_lab" / "results" / "cpu_finalization"
MANIFEST_PATH = DESTINATION / "manifest.json"

REPORT_NAMES = (
    "cpu3-c1-debug-balanced-r1.json",
    "cpu3-c1-release-native-host-balanced-r1.json",
    "cpu3-c2-release-w1-r1.json",
    "cpu3-c2-release-w2-r1.json",
    "cpu3-c2-release-w3-r1.json",
    "cpu3-c2-generation-g1-m2.json",
    "cpu3-c2-generation-g3-m2.json",
    "cpu3-c3-profile-low-power-r1.json",
    "cpu3-c3-profile-low-power-r2.json",
    "cpu3-c3-profile-low-power-r3.json",
    "cpu3-c3-profile-quality-r1.json",
    "cpu3-c3-profile-quality-r2.json",
    "cpu3-c3-profile-quality-r3.json",
    "cpu3-c3-profile-reference-r1.json",
    "cpu3-c3-profile-reference-r2.json",
    "cpu3-c3-profile-reference-r3.json",
    "cpu3-c3-final-balanced-r1.json",
    "cpu3-c3-final-balanced-r2.json",
    "cpu3-c3-final-balanced-r3.json",
    "cpu-c2-generation-g2-m2.json",
    "cpu-c3-profile-low-power-w1-runtime-result.json",
    "cpu-c3-profile-quality-w4-runtime-result.json",
    "dev-storage-completion-single-scan.json",
    "dev-worker-side-page-decode.json",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    arguments = parser.parse_args()

    missing = [name for name in REPORT_NAMES if not (arguments.source / name).is_file()]
    if missing:
        for name in missing:
            print(f"WT_TERRAIN_CPU_EVIDENCE_MISSING {name}")
        return 1

    DESTINATION.mkdir(parents=True, exist_ok=True)
    expected = set(REPORT_NAMES) | {MANIFEST_PATH.name}
    for stale in DESTINATION.glob("*.json"):
        if stale.name not in expected:
            stale.unlink()
    retained_bytes = 0
    reports = []
    for name in REPORT_NAMES:
        destination = DESTINATION / name
        shutil.copy2(arguments.source / name, destination)
        size = destination.stat().st_size
        retained_bytes += size
        reports.append(
            {
                "name": name,
                "bytes": size,
                "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            }
        )

    manifest = {
        "schema": "world_transvoxel.terrain_lab.cpu_finalization_manifest.v1",
        "report_count": len(reports),
        "reports": reports,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8")
    manifest_sha256 = hashlib.sha256(MANIFEST_PATH.read_bytes()).hexdigest()

    print(
        "WT_TERRAIN_CPU_EVIDENCE_RETAINED "
        f"reports={len(REPORT_NAMES)} bytes={retained_bytes} "
        f"manifest_sha256={manifest_sha256}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
