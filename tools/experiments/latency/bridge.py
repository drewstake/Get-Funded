"""Loopback-only transport for detached latency diagnostics. No DataStore writes."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'output/latency-20261027'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = self.path.strip('/').split('/')
        if len(parts) == 2 and parts[0] == 'bundle' and parts[1] in ('baseline', 'candidate'):
            base = OUT/'baseline/original' if parts[1] == 'baseline' else ROOT/'src'
            value = {p.stem: re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.(\w+)\)',
                                   r'require(script.Parent.\1)', p.read_text(encoding='utf-8-sig'))
                     for p in base.rglob('*.luau') if '.server.' not in p.name and '.client.' not in p.name}
            data = json.dumps(value).encode()
        elif self.path == '/release':
            manifest = json.loads((ROOT/'build/place-manifest.json').read_text())
            data = json.dumps([dict(row, source=(ROOT/row['file']).read_text(encoding='utf-8-sig')) for row in manifest['scripts']]).encode()
        elif self.path == '/checkpoint':
            data = (OUT/'saved-checkpoint.json').read_bytes()
        elif len(parts) == 2 and parts[0] == 'script' and re.fullmatch(r'[a-z0-9_-]+\.luau', parts[1]):
            data = (ROOT/'tools/experiments/latency'/parts[1]).read_bytes()
        else:
            self.send_error(404); return
        self.send_response(200); self.end_headers(); self.wfile.write(data)

    def do_POST(self):
        name = self.path.strip('/')
        size = int(self.headers.get('Content-Length', '0'))
        if not re.fullmatch(r'[a-z0-9-]+\.json', name) or not 0 < size <= 40000000:
            self.send_error(400); return
        dest = OUT/name
        if dest.exists():
            self.send_error(409); return
        value = json.loads(self.rfile.read(size))
        dest.write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv)>1 else 8818), Handler).serve_forever()
