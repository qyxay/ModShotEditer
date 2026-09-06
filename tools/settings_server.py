#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ModShot 运行时设置 — 本地 HTTP 服务器 (零依赖)

REST API:
  GET  /          → HTML 控制面板
  GET  /schema    → schema.json (游戏导出的设置定义)
  GET  /settings  → runtime.json (当前设置值)
  POST /settings  → 写入 runtime.json (游戏热重载自动应用)

用法: python tools/settings_server.py [端口]
"""
import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETTINGS_DIR = ROOT / "OneShot" / "mods" / "mod" / "settings"
SCHEMA_FILE = SETTINGS_DIR / "schema.json"
RUNTIME_FILE = SETTINGS_DIR / "runtime.json"
HTML_FILE = Path(__file__).resolve().parent / "settings_gui.html"

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path, ctype):
        if not path.exists():
            self.send_error(404)
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send_file(HTML_FILE, "text/html; charset=utf-8")
        elif self.path == "/schema":
            if SCHEMA_FILE.exists():
                self._send_file(SCHEMA_FILE, "application/json; charset=utf-8")
            else:
                self._send_json({"error": "schema.json 不存在, 请先启动游戏一次"}, 404)
        elif self.path == "/settings":
            if RUNTIME_FILE.exists():
                self._send_file(RUNTIME_FILE, "application/json; charset=utf-8")
            else:
                self._send_json({}, 200)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/settings":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            try:
                data = json.loads(raw.decode("utf-8"))
            except Exception as e:
                self._send_json({"error": str(e)}, 400)
                return
            SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
            RUNTIME_FILE.write_text(
                json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            self._send_json({"ok": True, "count": len(data)})
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


def main():
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"ModShot 设置服务器: http://127.0.0.1:{PORT}/  (Ctrl+C 停止)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()


if __name__ == "__main__":
    main()
