"""Публикация поста в сообщество VK, в том числе отложенная.

Использование:
    python tools/vk_publish.py --file docs/community/drafts/... --defer-hours 24
    python tools/vk_publish.py --text "Всем привет! ..." --defer-hours 24
    python tools/vk_publish.py --file post.txt   # опубликовать сразу

Токен берётся из .secrets/vk-api.token (gitignored). Для публикации в группу
нужен пользовательский токен администратора (scope wall, groups, offline).
Групповой токен отдаёт error 27 на wall.get и для публикации не подходит.
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKEN_PATH = ROOT / ".secrets" / "vk-api.token"
GROUP_ID = -230399307
API = "https://api.vk.com/method/wall.post"
VERSION = "5.199"


def load_token() -> str:
    return TOKEN_PATH.read_text(encoding="utf-8").strip()


def post(message: str, publish_date: int | None = None) -> dict:
    params = {
        "owner_id": GROUP_ID,
        "from_group": 1,
        "message": message,
        "v": VERSION,
        "access_token": load_token(),
    }
    if publish_date:
        params["publish_date"] = int(publish_date)
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(API, data=data)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--text", help="текст поста")
    ap.add_argument("--file", help="файл с текстом поста")
    ap.add_argument("--defer-hours", type=float, default=0.0,
                    help="отложить публикацию на N часов (0 = сразу)")
    args = ap.parse_args()

    if args.file:
        text = Path(args.file).read_text(encoding="utf-8").strip()
    elif args.text:
        text = args.text
    else:
        text = sys.stdin.read().strip()
    if not text:
        ap.error("нужен --text или --file")

    publish_date = None
    if args.defer_hours > 0:
        publish_date = time.time() + args.defer_hours * 3600

    result = post(text, publish_date)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result.get("error"):
        sys.exit(1)


if __name__ == "__main__":
    main()
