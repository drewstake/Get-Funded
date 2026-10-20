"""Loopback transport for market alert installation and isolated Studio validation."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/market-alert-20261019'
BACK = ROOT / 'backups/market-alert-20261019'
OUT.mkdir(exist_ok=True)
BACK.mkdir(exist_ok=True)
FILES = {
    'ReplicatedStorage.MarketReign.MarketEventBanner': 'MarketEventBanner.luau',
    'ReplicatedStorage.MarketReign.MarketClient': 'MarketClient.luau',
    'ReplicatedStorage.MarketReign.TerminalUI': 'TerminalUI.luau',
    'ServerScriptService.MarketReign.MarketServer': 'MarketServer.server.luau',
}

def digest(source):
    return hashlib.sha256(source.replace('\r\n', '\n').encode()).hexdigest()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/bundle':
            value = {}
            for path, filename in FILES.items():
                source = (ROOT / 'src' / filename).read_text(encoding='utf-8-sig')
                prior = BACK / filename
                value[path] = {'Source': source, 'Hash': digest(source),
                               'ExpectedHash': digest(prior.read_text(encoding='utf-8-sig')) if prior.exists() else False}
        elif self.path == '/validate':
            value = (ROOT / 'tools/market-alert/validate.luau').read_text(encoding='utf-8-sig')
        else:
            self.send_error(404)
            return
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        allowed = {'private-studio-before.json': BACK, 'installed.json': OUT,
                   'validation.json': OUT, 'live-validation.json': OUT}
        name = self.path.lstrip('/')
        if name not in allowed:
            self.send_error(404)
            return
        target = allowed[name] / name
        if name.startswith('private-') and target.exists():
            self.send_error(409)
            return
        size = int(self.headers['Content-Length'])
        if size > 2000000:
            self.send_error(413)
            return
        value = json.loads(self.rfile.read(size))
        target.write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8811), Handler).serve_forever()
