"""Loopback source transport and validation reports; no cloud or datastore operations."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
BACK = ROOT / 'backups/public-bot-information-20261019'
OUT = ROOT / 'output/public-bot-information-20261019'
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
        elif self.path == '/release':
            value = {}
            for name in MODULES:
                source = (ROOT / 'src' / (name + '.luau')).read_text(encoding='utf-8-sig')
                previous = BACK / 'src' / (name + '.luau')
                path = ('ReplicatedStorage' if name == 'MarketConfig' else 'ServerScriptService') + '.MarketReign.' + name
                value[path] = {'Source': source, 'Hash': sha(source),
                               'ExpectedHash': sha(previous.read_text(encoding='utf-8-sig')) if previous.exists() else False}
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

ThreadingHTTPServer(('127.0.0.1', 8801), Handler).serve_forever()
