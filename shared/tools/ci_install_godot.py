from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile


VERSION = "4.7.1-stable"
ARCHIVE_NAME = f"Godot_v{VERSION}_win64.exe.zip"
DOWNLOAD_URL = (
    "https://github.com/godotengine/godot-builds/releases/download/"
    f"{VERSION}/{ARCHIVE_NAME}"
)
EXPECTED_SHA256 = "c7a289051eaefb460b0106b60e9cd5bee0ef55fd102dcb2bed1eb356cf3d90a1"


def main() -> int:
    repository = Path(__file__).resolve().parents[2]
    install_directory = repository / ".ci" / "godot"
    archive_path = install_directory / ARCHIVE_NAME
    install_directory.mkdir(parents=True, exist_ok=True)
    if not archive_path.exists() or sha256(archive_path) != EXPECTED_SHA256:
        with urllib.request.urlopen(DOWNLOAD_URL) as response:
            with archive_path.open("wb") as archive:
                shutil.copyfileobj(response, archive)
    actual_hash = sha256(archive_path)
    if actual_hash != EXPECTED_SHA256:
        print(
            f"Godot archive hash mismatch: expected {EXPECTED_SHA256}, got {actual_hash}",
            file=sys.stderr,
        )
        return 1
    with zipfile.ZipFile(archive_path) as archive:
        archive.extractall(install_directory)
    executables = sorted(install_directory.glob("Godot*.exe"))
    if not executables:
        print("Godot executable was not found after extraction.", file=sys.stderr)
        return 1
    executable = executables[0]
    github_path = os.environ.get("GITHUB_PATH")
    if github_path:
        with Path(github_path).open("a", encoding="utf-8") as output:
            output.write(str(install_directory) + "\n")
    print(executable)
    return 0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
