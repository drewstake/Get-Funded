"""Loopback transport for source backups, detached tests and an edit-only installer."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib, json, re

ROOT = Path(__file__).resolve().parents[1]
BACK = ROOT / 'backups/bots-refresh-20261015'
OUT = ROOT / 'output/bots-refresh-20261015'
NAMES = ['MarketEngine', 'BotPopulation', 'WorldCheckpoint', 'WorldService',
         'BotRefresh', 'OwnerBotsCommand', 'BotRefreshTests']
PATHS = {f'ServerScriptService.MarketReign.{n}': f'{n}.luau' for n in NAMES}
PATHS['ServerScriptService.MarketReign.MarketServer'] = 'MarketServer.server.luau'

def sha(s): return hashlib.sha256(s.replace('\r\n', '\n').encode()).hexdigest()

class Handler(BaseHTTPRequestHandler):
    chunks = {}
    def do_GET(self):
        if self.path == '/bundle':
            result = {p.stem: re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.(\w+)\)', r'require(script.Parent.\1)', p.read_text(encoding='utf-8-sig'))
                      for p in (ROOT/'src').glob('*.luau') if '.server.' not in p.name and '.client.' not in p.name}
        elif self.path == '/checkpoint':
            result = json.loads((BACK/'private-checkpoint.json').read_text())
        elif self.path == '/release':
            old = json.loads((BACK/'private-studio-sources.json').read_text())['Sources']
            result = {}
            for path, name in PATHS.items():
                source = (ROOT/'src'/name).read_text(encoding='utf-8-sig')
                result[path] = {'Source': source, 'Hash': sha(source), 'ExpectedHash': sha(old[path]) if path in old else False,
                                'ClassName': 'Script' if '.server.' in name else 'ModuleScript'}
        else:
            self.send_error(404); return
        body = json.dumps(result).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        name = self.path.lstrip('/')
        if not re.fullmatch(r'[a-z0-9-]+\.json', name): self.send_error(404); return
        size = int(self.headers['Content-Length'])
        if size > 64000000: self.send_error(413); return
        value = json.loads(self.rfile.read(size))
        if isinstance(value, dict) and set(value) == {'Index', 'Total', 'Data'}:
            held = self.chunks.setdefault(name, {})
            held[value['Index']] = value['Data']
            if len(held) < value['Total']:
                self.send_response(200); self.end_headers(); self.wfile.write(b'PART'); return
            value = json.loads(''.join(held[i] for i in range(1, value['Total']+1)))
            del self.chunks[name]
        target = BACK if name.startswith('private-') else OUT
        (target/name).write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8799), Handler).serve_forever()
