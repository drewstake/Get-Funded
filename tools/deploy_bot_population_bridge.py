"""Loopback transfer for the explicitly authorized bot population deployment."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib, json, re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/bot-population-deployment-20261014'
BACKUP = ROOT / 'backups/bot-population-deployment-20261014'
OUT.mkdir(exist_ok=True)
BACKUP.mkdir(exist_ok=True)
(BACKUP / '.gitignore').write_text('*\n')
PATHS = {
    'ReplicatedStorage.MarketReign.MarketConfig': 'MarketConfig',
    'ServerScriptService.MarketReign.Participants': 'Participants',
    'ServerScriptService.MarketReign.BotPopulation': 'BotPopulation',
    'ServerScriptService.MarketReign.WorldCheckpoint': 'WorldCheckpoint',
}

def sha(source):
    return hashlib.sha256(source.replace('\r\n', '\n').encode()).hexdigest()

def read_source(name):
    return (ROOT / 'src' / (name + '.luau')).read_text(encoding='utf-8-sig')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/release':
            original = json.loads((BACKUP / 'studio-source.json').read_text())['Sources']
            result = {p: {'Source': read_source(n), 'Hash': sha(read_source(n)),
                          'ExpectedHash': sha(original[p]) if p in original else False}
                      for p, n in PATHS.items()}
        elif self.path == '/bundle':
            original = json.loads((BACKUP / 'studio-source.json').read_text())['Sources']
            result = {p.split('.')[-1]: s for p, s in original.items()}
            for n in PATHS.values():
                result[n] = read_source(n)
            for f in (ROOT / 'src').glob('*Tests.luau'):
                result[f.stem] = f.read_text(encoding='utf-8-sig')
            result['TestLiquidity'] = read_source('TestLiquidity')
            result['DryRunBotPopulation'] = (ROOT / 'tools/DryRunBotPopulation.luau').read_text()
            result = {n: re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.([\w]+)\)', r'require(script.Parent.\1)', s) for n, s in result.items()}
        else:
            self.send_error(404); return
        body = json.dumps(result).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        name = self.path.lstrip('/')
        if not re.fullmatch(r'[a-z0-9-]+\.json', name):
            self.send_error(404); return
        size = int(self.headers.get('Content-Length', 0))
        if size > 32000000:
            self.send_error(413); return
        result = json.loads(self.rfile.read(size))
        target = BACKUP if name in ['studio-source.json', 'live-checkpoint.json'] else OUT
        path = target / name
        if target == BACKUP and path.exists():
            self.send_error(409); return
        path.write_text(json.dumps(result, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

print('Deployment bridge listening on 127.0.0.1:8799', flush=True)
ThreadingHTTPServer(('127.0.0.1', 8799), Handler).serve_forever()
