"""Снимок проекта в папку versions/.

Складывает рабочую версию в zip, чтобы к ней можно было вернуться. Внутри
архива — одна папка с меткой версии и инструкцией; ярлыки Windows не попадают
в снимок, потому что они указывают на живую папку проекта.

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
SKIP_SUFFIXES = {".zip", ".exe", ".pck", ".log", ".lnk"}

HOWTO = """КАК ЗАПУСТИТЬ ЭТУ ВЕРСИЮ
===========================

1. Распакуйте архив целиком в любую папку (правый клик -> «Извлечь все»).
   Не запускайте файлы прямо из архива: Windows распаковывает их во временную
   папку, и игра не найдёт проект.

2. В распакованной папке запустите «Запустить игру.bat».
   Он сам подставит путь к этой копии проекта.

3. Godot должен лежать в C:\\Godot\\Godot_v4.7.2-stable_win64.exe.
   Если путь другой — откройте .bat блокнотом и поправьте строку GODOT.

Проверить версию: в папке есть docs/memory/context.md — там состояние на момент
снимка, и versions/README.md в основном проекте — список всех версий.
"""


def main() -> None:
    label = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
    description = sys.argv[2] if len(sys.argv) > 2 else ""
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    folder = f"{stamp}_{label}"
    VERSIONS.mkdir(exist_ok=True)
    target = VERSIONS / f"{folder}.zip"

    files = 0
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(f"{folder}/КАК ЗАПУСТИТЬ.txt", HOWTO)
        for path in ROOT.rglob("*"):
            if path.is_dir():
                continue
            relative = path.relative_to(ROOT)
            if any(part in SKIP_DIRS for part in relative.parts):
                continue
            if path.suffix.lower() in SKIP_SUFFIXES:
                continue
            archive.write(path, f"{folder}/{relative.as_posix()}")
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
            "Каждый zip разворачивается в отдельную папку и содержит инструкцию\n"
            "«КАК ЗАПУСТИТЬ.txt». Запускать файлы прямо из архива нельзя.\n\n"
            "| Файл | Метка | Что внутри | Файлов | Размер |\n"
            "|---|---|---|---|---|\n",
            encoding="utf-8",
        )
    with index.open("a", encoding="utf-8") as handle:
        handle.write(f"| `{name}` | {label} | {description} | {files} | {size_kb} КБ |\n")


if __name__ == "__main__":
    main()
