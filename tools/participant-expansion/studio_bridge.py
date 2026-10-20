"""Loopback source transport and validation reports; no cloud or datastore operations."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
BACK = ROOT / 'backups/participant-expansion-20261019'
OUT = ROOT / 'output/participant-expansion-20261019'
MODULES = ['MarketConfig', 'MarketEngine', 'Participants', 'BotSignals', 'BotLiquidity',
           'WorldCheckpoint', 'BotPopulationTests', 'BotSignalsTests', 'BotFairnessTests',
           'BotPublicInformationTests']

def sha(source):
    return hashlib.sha256(source.replace('\r\n', '\n').encode()).hexdigest()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/bundle':
            value = {p.stem: re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.(\w+)\)',
                                   r'require(script.Parent.\1)', p.read_text(encoding='utf-8-sig'))
                     for p in (ROOT / 'src').glob('*.luau') if '.server.' not in p.name and '.client.' not in p.name}
        elif self.path == '/targets':
            value = json.loads((OUT/'targets.json').read_text())
        elif self.path == '/release':
            value = json.loads((OUT/'release.json').read_text())
        elif self.path == '/checkpoint':
            value = json.loads((BACK/'private-studio-checkpoint.json').read_text())
        else:
            self.send_error(404)
            return
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        name = self.path.lstrip('/')
        if name in ('benchmark-progress.json', 'benchmark-final-progress.json', 'studio-progress.json', 'studio-final-progress.json'):
            self.send_error(409, 'Superseded by final participant benchmark')
            return
        size = int(self.headers.get('Content-Length', '0'))
        if not re.fullmatch(r'[a-z0-9-]+\.json', name) or size > 16000000:
            self.send_error(400)
            return
        path = (BACK if name.startswith('private-') else OUT) / name
        if name.startswith('private-') and path.exists():
            self.send_error(409)
            return
        value = json.loads(self.rfile.read(size))
        path.write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8807), Handler).serve_forever()
