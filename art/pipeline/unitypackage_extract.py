#!/usr/bin/env python3
"""Pull FBX, textures and audio out of a .unitypackage (D-02 asset pipeline). Owner: Lane D.

A .unitypackage is a gzip tar whose top level is one folder per Unity GUID:
    <guid>/asset       the file itself
    <guid>/pathname    first line = original path, e.g. Assets/CityRuins/Models/Building_A.fbx
Unity materials, prefabs, scenes and C# scripts are skipped on purpose: Godot rebuilds the
materials from art/materials/ (toon). Nothing is executed and nothing is written outside --out.

Usage (Python 3.10+, standard library only):
    python -I art/pipeline/unitypackage_extract.py assets/_source/city_ruins.unitypackage \
        --out assets/environment/city/city_ruins [--strip "Assets/CityRuins"] [--snake] [--dry-run]

Always fill a row in assets/LICENSES.md before committing what this produces.
"""
from __future__ import annotations

import argparse
import re
import sys
import tarfile
from pathlib import Path, PurePosixPath

KEEP = {
    ".fbx", ".obj", ".glb", ".gltf", ".dae", ".blend",
    ".png", ".jpg", ".jpeg", ".tga", ".tif", ".tiff", ".psd", ".exr", ".hdr", ".bmp",
    ".wav", ".ogg", ".mp3", ".flac",
}


def snake(name: str) -> str:
    stem, dot, ext = name.rpartition(".")
    if not dot:
        stem, ext = name, ""
    stem = re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", stem)
    stem = re.sub(r"[^A-Za-z0-9]+", "_", stem).strip("_").lower() or "file"
    return f"{stem}.{ext.lower()}" if ext else stem


def plan(package: Path, strip: str, use_snake: bool) -> list[tuple[str, PurePosixPath]]:
    """Return [(member name of the asset blob, relative output path)]."""
    pairs: list[tuple[str, PurePosixPath]] = []
    with tarfile.open(package, "r:gz") as tar:
        names = {m.name.lstrip("./") for m in tar.getmembers()}
        for name in sorted(names):
            if not name.endswith("/pathname"):
                continue
            guid = name[: -len("/pathname")]
            blob = f"{guid}/asset"
            if blob not in names:
                continue  # folders have no asset blob
            f = tar.extractfile(tar.getmember(_member(tar, name)))
            if f is None:
                continue
            original = f.read().decode("utf-8", "replace").splitlines()[0].strip()
            path = PurePosixPath(original)
            if path.suffix.lower() not in KEEP:
                continue
            rel = str(path)
            if strip and rel.startswith(strip.rstrip("/") + "/"):
                rel = rel[len(strip.rstrip("/")) + 1:]
            elif rel.startswith("Assets/"):
                rel = rel[len("Assets/"):]
            parts = [p for p in PurePosixPath(rel).parts if p not in ("", ".", "..")]
            if use_snake:
                parts = [snake(p) for p in parts]
            if parts:
                pairs.append((blob, PurePosixPath(*parts)))
    return pairs


def _member(tar: tarfile.TarFile, name: str) -> str:
    for cand in (name, "./" + name):
        try:
            tar.getmember(cand)
            return cand
        except KeyError:
            pass
    raise KeyError(name)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("package", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--strip", default="", help="path prefix to drop, e.g. Assets/CityRuins")
    ap.add_argument("--snake", action="store_true", help="rename files and folders to snake_case")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    out = a.out.resolve()
    pairs = plan(a.package, a.strip, a.snake)
    if not pairs:
        print("nothing to extract (no FBX / texture / audio files found)")
        return 1
    with tarfile.open(a.package, "r:gz") as tar:
        for blob, rel in pairs:
            dest = (out / Path(*rel.parts)).resolve()
            if out not in dest.parents:
                print(f"skip (outside --out): {rel}")
                continue
            print(("would write " if a.dry_run else "write ") + str(dest.relative_to(out)))
            if a.dry_run:
                continue
            src = tar.extractfile(tar.getmember(_member(tar, blob)))
            if src is None:
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "wb") as fh:
                while chunk := src.read(1 << 20):
                    fh.write(chunk)
    print(f"{len(pairs)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
