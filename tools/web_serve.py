#!/usr/bin/env python3
"""Локальный статический сервер для проверки Web-сборки OneLife.

Без COOP/COEP (сборка однопоточная). Отдаёт правильные MIME для .wasm/.pck/.js.
Запуск: python tools/web_serve.py [порт]
"""
import http.server
import socketserver
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
ROOT = os.path.abspath(ROOT)


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".html": "text/html",
        ".png": "image/png",
        ".json": "application/json",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, *args):
        pass


if not os.path.isdir(ROOT):
    sys.stderr.write(f"Нет папки сборки: {ROOT}\nСначала выполните экспорт.\n")
    sys.exit(1)

print(f"Serving {ROOT} on http://0.0.0.0:{PORT}/  (локально: http://127.0.0.1:{PORT}/)", flush=True)
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.serve_forever()
