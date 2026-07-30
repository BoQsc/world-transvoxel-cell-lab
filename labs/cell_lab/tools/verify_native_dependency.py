from __future__ import annotations

import argparse
import configparser
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


MANIFEST_PATH = Path(
    "addons/world_transvoxel_cell_lab/standards/native_dependency_manifest.json"
)
EXPECTED_SCHEMA = "world_transvoxel.cell_lab.native_dependency_manifest.v1"
PLUGIN_PATH = Path("addons/world_transvoxel/plugin.cfg")
GDEXTENSION_PATH = Path("addons/world_transvoxel/world_transvoxel.gdextension")
OFFICIAL_SOURCE_PATH = Path(
    "addons/world_transvoxel/thirdparty/transvoxel_mit/Transvoxel.cpp"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-checkout",
        type=Path,
        help="Verify the pinned source commit and trees in an existing checkout.",
    )
    parser.add_argument(
        "--clone-source",
        type=Path,
        help="Clone the pinned source into this directory before verifying it.",
    )
    arguments = parser.parse_args()
    repository = Path(__file__).resolve().parents[3]
    manifest = load_json(repository / MANIFEST_PATH)
    errors: list[str] = []
    if manifest.get("schema") != EXPECTED_SCHEMA:
        errors.append("native dependency manifest schema changed")
    verify_plugin(repository, manifest, errors)
    verify_gdextension(repository, manifest, errors)
    verify_artifacts(repository, manifest, errors)
    source_checkout = arguments.source_checkout
    if arguments.clone_source is not None:
        clone_target = arguments.clone_source.resolve()
        if repository not in clone_target.parents:
            errors.append("--clone-source must remain inside the labs repository")
        else:
            source_checkout = clone_source(manifest, clone_target)
    if source_checkout is not None:
        verify_source(source_checkout.resolve(), manifest, errors)
    if errors:
        for error in errors:
            print(f"WT_NATIVE_DEPENDENCY_FAIL {error}", file=sys.stderr)
        return 1
    print(
        "WT_NATIVE_DEPENDENCY_PASS "
        + json.dumps(
            {
                "source_commit": manifest["source"]["commit"],
                "backend_id": manifest["backend"]["id"],
                "backend_upstream_revision": manifest["backend"][
                    "upstream_revision"
                ],
                "artifact_count": len(manifest["artifacts"]),
                "source_verified": source_checkout is not None,
            },
            sort_keys=True,
        )
    )
    return 0


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as source:
        value = json.load(source)
    if not isinstance(value, dict):
        raise RuntimeError(f"{path} must contain a JSON object")
    return value


def verify_plugin(repository: Path, manifest: dict, errors: list[str]) -> None:
    parser = configparser.ConfigParser()
    parser.read(repository / PLUGIN_PATH, encoding="utf-8")
    expected = manifest.get("plugin", {})
    if unquote(parser.get("plugin", "name", fallback="")) != expected.get("name"):
        errors.append("vendored plugin name differs from the manifest")
    if unquote(parser.get("plugin", "version", fallback="")) != expected.get("version"):
        errors.append("vendored plugin version differs from the manifest")


def verify_gdextension(repository: Path, manifest: dict, errors: list[str]) -> None:
    parser = configparser.ConfigParser()
    parser.read(repository / GDEXTENSION_PATH, encoding="utf-8")
    actual_minimum = unquote(
        parser.get("configuration", "compatibility_minimum", fallback="")
    )
    expected_minimum = manifest.get("toolchain", {}).get(
        "godot_compatibility_minimum", ""
    )
    if actual_minimum != expected_minimum:
        errors.append("GDExtension compatibility minimum differs from the manifest")
    libraries = dict(parser.items("libraries")) if parser.has_section("libraries") else {}
    for artifact in manifest.get("artifacts", []):
        configuration = artifact.get("configuration", "")
        architecture = artifact.get("architecture", "")
        platform = artifact.get("platform", "")
        key = f"{platform}.{configuration.removeprefix('template_')}.{architecture}"
        expected_path = "res://" + artifact.get("path", "").replace("\\", "/")
        if unquote(libraries.get(key, "")) != expected_path:
            errors.append(f"GDExtension library mapping differs for {key}")


def verify_artifacts(repository: Path, manifest: dict, errors: list[str]) -> None:
    artifacts = manifest.get("artifacts", [])
    if not isinstance(artifacts, list) or not artifacts:
        errors.append("native dependency manifest has no artifacts")
        return
    for artifact in artifacts:
        relative_path = Path(artifact.get("path", ""))
        path = repository / relative_path
        if not path.is_file():
            errors.append(f"native artifact is missing: {relative_path}")
            continue
        if path.stat().st_size != int(artifact.get("bytes", -1)):
            errors.append(f"native artifact byte size changed: {relative_path}")
        if sha256(path) != artifact.get("sha256"):
            errors.append(f"native artifact SHA-256 changed: {relative_path}")


def clone_source(manifest: dict, target: Path) -> Path:
    source = manifest["source"]
    if target.exists():
        shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    run(["git", "clone", "--filter=blob:none", "--no-checkout", source["repository"], str(target)])
    run(["git", "-C", str(target), "fetch", "--depth", "1", "origin", source["commit"]])
    run(["git", "-C", str(target), "checkout", "--detach", source["commit"]])
    return target


def verify_source(checkout: Path, manifest: dict, errors: list[str]) -> None:
    source = manifest.get("source", {})
    expected_values = {
        "commit": source.get("commit", ""),
        "addon_source_tree": source.get("addon_source_tree", ""),
        "addon_thirdparty_tree": source.get("addon_thirdparty_tree", ""),
        "godot_cpp_revision": source.get("godot_cpp_revision", ""),
    }
    actual_values = {
        "commit": git_output(checkout, "rev-parse", "HEAD"),
        "addon_source_tree": git_output(
            checkout, "rev-parse", "HEAD:addons/world_transvoxel/src"
        ),
        "addon_thirdparty_tree": git_output(
            checkout, "rev-parse", "HEAD:addons/world_transvoxel/thirdparty"
        ),
        "godot_cpp_revision": git_output(
            checkout, "rev-parse", "HEAD:thirdparty/godot-cpp"
        ),
    }
    for key, expected in expected_values.items():
        if actual_values[key] != expected:
            errors.append(f"pinned source {key} differs from the manifest")
    source_plugin = configparser.ConfigParser()
    source_plugin.read(
        checkout / "addons/world_transvoxel/plugin.cfg", encoding="utf-8"
    )
    if unquote(source_plugin.get("plugin", "version", fallback="")) != manifest["plugin"]["version"]:
        errors.append("pinned source plugin version differs from the manifest")
    official_source = checkout / OFFICIAL_SOURCE_PATH
    if not official_source.is_file():
        errors.append("official Transvoxel source is missing from pinned source")
    elif sha256(official_source) != manifest["backend"]["official_source_sha256"]:
        errors.append("official Transvoxel source SHA-256 differs from the manifest")


def git_output(checkout: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(checkout), *arguments], text=True
    ).strip()


def unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
