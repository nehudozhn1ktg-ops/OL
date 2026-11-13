"""Снимок проекта в папку versions/.

Складывает рабочую версию в zip, чтобы к ней можно было вернуться, даже если
git-история уедет вперёд. Служебные и тяжёлые папки не попадают в архив.

Запуск:
    python tools/snapshot.py v0.2 "краткое описание"
"""

import datetime
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSIONS = ROOT / "versions"
SKIP_DIRS = {".git", ".godot", "versions", "__pycache__", ".vs"}
SKIP_SUFFIXES = {".zip", ".exe", ".pck", ".log"}


def main() -> None:
    label = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
    description = sys.argv[2] if len(sys.argv) > 2 else ""
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    VERSIONS.mkdir(exist_ok=True)
    target = VERSIONS / f"{stamp}_{label}.zip"

    files = 0
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in ROOT.rglob("*"):
            if path.is_dir():
                continue
            relative = path.relative_to(ROOT)
            if any(part in SKIP_DIRS for part in relative.parts):
                continue
            if path.suffix.lower() in SKIP_SUFFIXES:
                continue
            archive.write(path, relative.as_posix())
            files += 1

    size_kb = round(target.stat().st_size / 1024)
    print(f"снимок: {target.name}  файлов {files}, {size_kb} КБ")
    if description:
        _append_index(target.name, label, description, files, size_kb)


def _append_index(name: str, label: str, description: str, files: int, size_kb: int) -> None:
    index = VERSIONS / "README.md"
    if not index.exists():
        index.write_text(
            "# Версии проекта\n\n"
            "Каждый zip — рабочее состояние на момент снимка. Разворачивается\n"
            "распаковкой в отдельную папку; Godot открывает `project.godot`.\n\n"
            "| Файл | Метка | Что внутри | Файлов | Размер |\n"
            "|---|---|---|---|---|\n",
            encoding="utf-8",
        )
    with index.open("a", encoding="utf-8") as handle:
        handle.write(f"| `{name}` | {label} | {description} | {files} | {size_kb} КБ |\n")


if __name__ == "__main__":
    main()
