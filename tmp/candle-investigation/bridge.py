from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, re

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'backups/candle-investigation-20261015'
OUT = ROOT / 'output/candle-investigation-20261015'
PRIVATE.mkdir(exist_ok=True); OUT.mkdir(exist_ok=True)
(PRIVATE / '.gitignore').write_text('*\n')

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        name = self.path.lstrip('/')
        if not re.fullmatch(r'[a-z0-9-]+\.json', name):
            self.send_error(404); return
        size = int(self.headers.get('Content-Length', 0))
        if size > 32000000:
            self.send_error(413); return
        value = json.loads(self.rfile.read(size))
        target = PRIVATE if name.startswith('private-') else OUT
        (target / name).write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')
    def do_GET(self):
        if self.path == '/bundle':
            bundle={}
            for f in (ROOT/'src').glob('*.luau'):
                if '.server.' in f.name or '.client.' in f.name: continue
                bundle[f.stem]=re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.([\w]+)\)', r'require(script.Parent.\1)', f.read_text(encoding='utf-8-sig'))
            body=json.dumps(bundle).encode()
        elif self.path.startswith('/private-') and re.fullmatch(r'/private-[a-z0-9-]+\.json', self.path):
            body=(PRIVATE/self.path.lstrip('/')).read_bytes()
        else:
            self.send_error(404); return
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(body)
    def log_message(self, fmt, *args): print(fmt % args, flush=True)

print('Candle read-only investigation bridge 127.0.0.1:8796', flush=True)
ThreadingHTTPServer(('127.0.0.1', 8796), Handler).serve_forever()
