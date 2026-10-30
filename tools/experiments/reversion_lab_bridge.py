"""Loopback-only isolated Reversion lab sources, snapshots, and results."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2] / 'output' / 'reversion-20261021'
ROOT.mkdir(parents=True, exist_ok=True)
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def do_POST(self):
        parts = self.path.strip('/').split('/')
        if not parts or any(not p or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-. ' for c in p) or p in ('.', '..') for p in parts):
            self.send_error(400); return
        target = ROOT.joinpath(*parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        data = self.rfile.read(int(self.headers['Content-Length']))
        target.write_bytes(data)
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')
ThreadingHTTPServer(('127.0.0.1', 8820), Handler).serve_forever()
