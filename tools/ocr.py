"""OCR через Tesseract (русский + английский).

Использование:
  python tools/ocr.py <путь-к-картинке> [язык=rus+eng]

Печатает распознанный текст. Русский traineddata лежит в C:\\Users\\Admin\\.tessdata,
поэтому скрипт передаёт --tessdata-dir. Для точного текста с карточек/памяток.
"""

import subprocess
import sys

TESSERACT = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
TESSDATA = r"C:\Users\Admin\.tessdata"


def main() -> None:
    if len(sys.argv) < 2:
        print("использование: python tools/ocr.py <картинка> [язык]")
        sys.exit(2)
    path = sys.argv[1]
    lang = sys.argv[2] if len(sys.argv) > 2 else "rus+eng"
    result = subprocess.run(
        [TESSERACT, path, "stdout", "-l", lang, "--tessdata-dir", TESSDATA],
        capture_output=True, text=True, encoding="utf-8",
    )
    sys.stdout.write(result.stdout)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)


if __name__ == "__main__":
    main()
