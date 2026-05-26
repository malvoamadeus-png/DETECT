from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class AppPaths:
    root: Path
    data: Path
    raw: Path
    processed: Path
    exports: Path


def find_root() -> Path:
    current = Path(__file__).resolve()
    for parent in current.parents:
        if (parent / "backend").exists() and (parent / "data").exists():
            return parent
    raise RuntimeError("Could not locate DETECT project root.")


def get_paths() -> AppPaths:
    root = find_root()
    data = root / "data"
    return AppPaths(
        root=root,
        data=data,
        raw=data / "raw",
        processed=data / "processed",
        exports=data / "exports",
    )


def ensure_data_dirs() -> AppPaths:
    paths = get_paths()
    for folder in (paths.raw, paths.processed, paths.exports):
        folder.mkdir(parents=True, exist_ok=True)
    return paths

