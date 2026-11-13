"""Готовит иконки интерфейса: убирает белый фон, обрезает и уменьшает.

Исходники — из «Компоненты для нейросети/Памятка и иконки/Иконки».
Результат — assets/ui/<name>.png с прозрачным фоном, сторона <= 128 px.
Запуск: python tools/prepare_ui_icons.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "assets" / "ui"
NAMES = ["damage", "armor", "move", "action", "attack_range", "aura", "wound"]


def strip_white(image: Image.Image) -> Image.Image:
    """Белый (и почти белый) фон -> прозрачность."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            if r > 238 and g > 238 and b > 238:
                pixels[x, y] = (r, g, b, 0)
    return rgba


def main() -> None:
    for name in NAMES:
        src = UI / f"{name}.png"
        if not src.exists():
            print(f"нет файла: {src}")
            continue
        image = strip_white(Image.open(src))
        bbox = image.getbbox()
        if bbox:
            image = image.crop(bbox)
        image.thumbnail((128, 128), Image.LANCZOS)
        image.save(src)
        print(f"{name}: {image.size[0]}x{image.size[1]}")


if __name__ == "__main__":
    main()
