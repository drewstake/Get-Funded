"""Loopback-only transport for the authorized Studio strategy update/playtest."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
BACK = ROOT / 'backups/legacy-retirement-20261018'
OUT = ROOT / 'output/legacy-retirement-20261018'
BACK.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)

def sha(text):
    return hashlib.sha256(text.replace('\r\n', '\n').encode()).hexdigest()

class Handler(BaseHTTPRequestHandler):
    chunks = {}

    def do_GET(self):
        if self.path == '/bundle':
            value = {p.stem: re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.(\w+)\)', r'require(script.Parent.\1)', p.read_text(encoding='utf-8-sig'))
                     for p in (ROOT / 'src').glob('*.luau') if '.server.' not in p.name and '.client.' not in p.name}
        elif self.path == '/release':
            manifest = json.loads((ROOT / 'output/legacy-retirement-20261018/release-manifest.json').read_text())
            old = json.loads((BACK / 'private-studio-sources.json').read_text())['Sources']
            value = {}
            for path, item in manifest['Modules'].items():
                source = (ROOT / item['File']).read_text(encoding='utf-8-sig')
                assert sha(source) == item['Hash'], path
                previous = old.get(path)
                assert (sha(previous) if previous is not None else None) in (item['PriorHash'], item['Hash']), path
                value[path] = {'Source': source, 'Hash': sha(source), 'ExpectedHash': sha(previous) if previous is not None else False, 'ClassName': 'ModuleScript'}
        elif self.path in ('/checkpoint', '/live-checkpoint', '/studio-checkpoint'):
            value = json.loads((BACK / ('private-live-checkpoint.json' if self.path == '/live-checkpoint' else 'private-studio-checkpoint.json')).read_text())
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
        if not re.fullmatch(r'[a-z0-9-]+\.json', name):
            self.send_error(404)
            return
        size = int(self.headers['Content-Length'])
        if size > 64000000:
            self.send_error(413)
            return
        value = json.loads(self.rfile.read(size))
        if isinstance(value, dict) and set(value) == {'Index', 'Total', 'Data'}:
            held = self.chunks.setdefault(name, {})
            held[value['Index']] = value['Data']
            if len(held) < value['Total']:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'PART')
                return
            value = json.loads(''.join(held[i] for i in range(1, value['Total'] + 1)))
            del self.chunks[name]
        path = (BACK if name.startswith('private-') else OUT) / name
        # Backups are immutable; rerunning may not replace the original evidence.
        if name.startswith('private-') and path.exists():
            self.send_error(409, 'Backup already exists')
            return
        path.write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8796), Handler).serve_forever()
