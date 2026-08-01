from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
EXECUTABLE_SUFFIXES = {".gd", ".tscn", ".gdshader", ".cfg"}

SCOPES = {
    "Cell Lab": (
        [
            ROOT / "addons" / "world_transvoxel_cell_lab",
            ROOT / "labs" / "cell_lab",
        ],
        [
            "addons/world_transvoxel_terrain_lab",
            "labs/terrain_lab",
            "WtTransvoxelTerrainLab",
        ],
    ),
    "Terrain Lab": (
        [
            ROOT / "addons" / "world_transvoxel_terrain_lab",
            ROOT / "labs" / "terrain_lab",
        ],
        [
            "addons/world_transvoxel_cell_lab",
            "labs/cell_lab",
            "WtTransvoxelCellLab",
        ],
    ),
}


def executable_files(roots: list[Path]) -> list[Path]:
    return sorted(
        path
        for root in roots
        for path in root.rglob("*")
        if path.is_file() and path.suffix in EXECUTABLE_SUFFIXES
    )


def main() -> int:
    failures: list[str] = []
    for scope_name, (roots, forbidden_fragments) in SCOPES.items():
        for path in executable_files(roots):
            source = path.read_text(encoding="utf-8")
            normalized = source.replace("\\", "/")
            for fragment in forbidden_fragments:
                if fragment in normalized:
                    failures.append(
                        f"{scope_name} dependency violation: "
                        f"{path.relative_to(ROOT)} contains {fragment!r}"
                    )

    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    expected_main = 'run/main_scene="res://labs/cell_lab/scenes/main.tscn"'
    if expected_main not in project:
        failures.append("project.godot no longer launches the Cell Lab scene")

    if failures:
        for failure in failures:
            print(f"WT_LAB_BOUNDARY_FAIL {failure}")
        return 1

    checked = sum(len(executable_files(roots)) for roots, _ in SCOPES.values())
    print(f"WT_LAB_BOUNDARY_PASS executable_files={checked}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
