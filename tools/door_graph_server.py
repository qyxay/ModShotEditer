# -*- coding: utf-8 -*-
# ============================================================
#  door_graph_server.py — 门连接可视化编辑器: 本地服务器
#
#  零依赖(Python 标准库), 手写 WebSocket(RFC 6455):
#    * GET /            -> door_graph.html (素白门连接图页面)
#    * GET /graph.json  -> 静态门连接图数据(预扫描生成)
#    * GET /live        -> live_state.json (游戏端实时状态, 兜底轮询用)
#    * GET /ws          -> WebSocket 推送: 游戏端 live_state.json 变化时
#                          实时推送给所有连接的网页
#    * POST /move       -> 写 event_modify.json (游戏端下一帧应用)
#
#  实时链路: 游戏端节流写 live_state.json -> 本服务器 200ms 轮询 mtime
#            -> WebSocket 推送给网页 -> 页面重绘/高亮。
#
#  启动: python door_graph_server.py
#  网页: http://127.0.0.1:8765
# ============================================================

import base64
import hashlib
import http.server
import json
import os
import socketserver
import socket
import threading
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(ROOT)  # tools/ -> 项目根
SETTINGS = os.path.join(PROJ, 'OneShot', 'mods', 'mod', 'settings')
LIVE_PATH = os.path.join(SETTINGS, 'live_state.json')
MODIFY_PATH = os.path.join(SETTINGS, 'event_modify.json')
GRAPH_PATH = os.path.join(SETTINGS, 'graph.json')
HTML_PATH = os.path.join(ROOT, 'door_graph.html')
PORT = 8765
WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

_clients = []          # 活跃 WebSocket socket
_clients_lock = threading.Lock()


def ws_send(sock, opcode, payload):
    """发送一个 WebSocket 帧(服务器->客户端不 mask)"""
    length = len(payload)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header += length.to_bytes(2, 'big')
    else:
        header.append(127)
        header += length.to_bytes(8, 'big')
    sock.sendall(bytes(header) + payload)


def ws_send_text(sock, text):
    ws_send(sock, 0x1, text.encode('utf-8'))


class DoorGraphHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    # ---------- HTTP ----------
    def do_GET(self):
        path = self.path.split('?')[0]
        if path in ('/', '/index.html'):
            self._serve_file(HTML_PATH, 'text/html; charset=utf-8')
        elif path == '/graph.json':
            self._serve_file(GRAPH_PATH, 'application/json; charset=utf-8')
        elif path == '/live':
            self._serve_file(LIVE_PATH, 'application/json; charset=utf-8')
        elif path == '/ws':
            self._handle_ws()
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path.split('?')[0] == '/move':
            try:
                length = int(self.headers.get('Content-Length', 0))
                req = json.loads(self.rfile.read(length).decode('utf-8'))
                # 校验: 至少包含事件 id; x/y/dir 可缺省(只改方向等)
                if isinstance(req, dict) and isinstance(req.get('ev'), (int, str)):
                    os.makedirs(SETTINGS, exist_ok=True)
                    with open(MODIFY_PATH, 'w', encoding='utf-8') as f:
                        json.dump(req, f, ensure_ascii=False)
                    self._json_response(200, {'ok': True})
                    return
            except (ValueError, OSError):
                pass
            self._json_response(400, {'ok': False, 'error': 'bad request'})
        else:
            self.send_error(404)

    # ---------- 工具 ----------
    def _serve_file(self, path, ctype):
        try:
            with open(path, 'rb') as f:
                data = f.read()
        except FileNotFoundError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def _json_response(self, code, obj):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # 静默, 避免刷屏

    # ---------- WebSocket ----------
    def _handle_ws(self):
        key = self.headers.get('Sec-WebSocket-Key')
        if not key:
            self.send_error(400)
            return
        accept = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode('ascii')).digest()
        ).decode('ascii')
        self.send_response(101)
        self.send_header('Upgrade', 'websocket')
        self.send_header('Connection', 'Upgrade')
        self.send_header('Sec-WebSocket-Accept', accept)
        self.end_headers()

        sock = self.connection
        with _clients_lock:
            _clients.append(sock)
        try:
            self._ws_read_loop(sock)
        finally:
            with _clients_lock:
                if sock in _clients:
                    _clients.remove(sock)
            try:
                sock.close()
            except OSError:
                pass

    def _ws_read_loop(self, sock):
        """读客户端帧: 处理 close/ping, 其余忽略"""
        sock.settimeout(None)
        while True:
            try:
                head = sock.recv(2)
                if len(head) < 2:
                    return
                b1, b2 = head[0], head[1]
                opcode = b1 & 0x0f
                length = b2 & 0x7f
                masked = (b2 & 0x80) != 0
                if length == 126:
                    ext = sock.recv(2)
                    if len(ext) < 2:
                        return
                    length = int.from_bytes(ext, 'big')
                elif length == 127:
                    ext = sock.recv(8)
                    if len(ext) < 8:
                        return
                    length = int.from_bytes(ext, 'big')
                mask = sock.recv(4) if masked else b''
                payload = b''
                while len(payload) < length:
                    chunk = sock.recv(length - len(payload))
                    if not chunk:
                        return
                    payload += chunk
                if masked and len(mask) == 4:
                    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
                if opcode == 0x8:      # close
                    return
                elif opcode == 0x9:    # ping -> pong
                    ws_send(sock, 0xA, payload)
            except OSError:
                return


def poll_loop():
    """轮询 live_state.json 的 mtime, 变化时推送给所有 WS 客户端"""
    last_mtime = None
    while True:
        try:
            if os.path.exists(LIVE_PATH):
                mtime = os.path.getmtime(LIVE_PATH)
                if mtime != last_mtime:
                    last_mtime = mtime
                    with open(LIVE_PATH, 'rb') as f:
                        data = f.read()
                    if data:
                        payload = b'{"type":"live","data":' + data + b'}'
                        with _clients_lock:
                            for s in list(_clients):
                                try:
                                    ws_send(s, 0x1, payload)
                                except OSError:
                                    pass
        except Exception:
            pass
        time.sleep(0.2)


class ThreadingServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == '__main__':
    threading.Thread(target=poll_loop, daemon=True).start()
    server = ThreadingServer(('127.0.0.1', PORT), DoorGraphHandler)
    print('Door graph server: http://127.0.0.1:%d' % PORT)
    print('live_state : %s' % LIVE_PATH)
    print('graph      : %s' % GRAPH_PATH)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
