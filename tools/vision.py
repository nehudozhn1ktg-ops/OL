"""Локальное зрение через Ollama (moondream).

Использование:
  python tools/vision.py <путь-к-картинке> [вопрос]

Читает картинку, отправляет её в Ollama (http://127.0.0.1:11434/api/generate)
и печатает текстовое описание. Модель: moondream (локально, бесплатно, приватно).

Зависимости: только stdlib (urllib, base64). Ollama должен быть запущен.
"""

import base64
import json
import sys
import urllib.request

OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
MODEL = "moondream"


def main() -> None:
    if len(sys.argv) < 2:
        print("использование: python tools/vision.py <картинка> [вопрос]")
        sys.exit(2)
    path = sys.argv[1]
    question = sys.argv[2] if len(sys.argv) > 2 else "Describe this image briefly."
    with open(path, "rb") as fh:
        image_b64 = base64.b64encode(fh.read()).decode("ascii")

    payload = {
        "model": MODEL,
        "prompt": question,
        "images": [image_b64],
        "stream": False,
        "options": {"num_predict": 120, "temperature": 0.0, "repeat_penalty": 1.5, "top_p": 0.9},
    }
    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=600) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    print(body.get("response", "").strip())


if __name__ == "__main__":
    main()
