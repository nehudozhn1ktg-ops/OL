"""Готовит тайлы для игры: убирает белый фон и обрезает по гексу.

Картинки приходят квадратными 1000x1000 с белым фоном. Для отрисовки нужен
прозрачный PNG ровно по границам гекса в пропорции flat-top (2 : sqrt(3)).
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "tiles"
OUT.mkdir(parents=True, exist_ok=True)

SRC = {
    "camp": r"C:\Users\Admin\.dsh\attachments\v1\objects\84\84381c3c0ba5ff48ee0ad9fd3da74e53db1f94f3532e62cabcc3974668b5d5aa",
    "forest": r"C:\Users\Admin\.dsh\attachments\v1\objects\ee\ee65dd491e1080054d3d8aa39690dbed92458309ec441a75d569e478998831b9",
    "grass": r"C:\Users\Admin\.dsh\attachments\v1\objects\49\4993433d21fd70389c2d9cd4fbfd59ed95c64b0fdd9c9e3b5487d446bfe59492",
    "fort": r"C:\Users\Admin\.dsh\attachments\v1\objects\07\07d0186c5ead0e3df5a81665629aa4e60d722606dec4138d142c61b99128b097",
    "flag": r"C:\Users\Admin\.dsh\attachments\v1\objects\02\02a98090ca693ee37cf6813f54871714f04cdc0a61c05006ae9450ced4e869d7",
    "water": r"C:\Users\Admin\.dsh\attachments\v1\objects\93\938bb45c1ba5feb032ca60bab9afee30dc438c72b34f453ed8a95e2c81096cae",
    "key": r"C:\Users\Admin\.dsh\attachments\v1\objects\cf\cf7aa5260165f3babcf69e727f876e06ef3cd55b373661d157033bf4ba682568",
}

TARGET = (512, 443)  # 2 : sqrt(3)


def main() -> None:
    for name, path in SRC.items():
        image = Image.open(path).convert("RGBA")
        pixels = image.load()
        width, height = image.size
        for y in range(height):
            for x in range(width):
                r, g, b, _a = pixels[x, y]
                if r > 236 and g > 236 and b > 236:
                    pixels[x, y] = (r, g, b, 0)
        bbox = image.getbbox()
        if bbox is None:
            print(f"{name}: пустая картинка")
            continue
        cropped = image.crop(bbox)
        # сохраняем пропорцию гекса: тянем незначительно
        resized = cropped.resize(TARGET, Image.LANCZOS)
        out = OUT / f"{name}.png"
        resized.save(out)
        print(f"{name}: {cropped.size} -> {resized.size}  {out.name}")


if __name__ == "__main__":
    main()
