"""Loopback-only evidence and detached validation transport; never calls trading APIs."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, re
ROOT = Path(__file__).resolve().parents[2]
BACK = ROOT / 'backups/execution-integrity-20261015'
OUT = ROOT / 'output/execution-integrity-20261015'
BACK.mkdir(exist_ok=True); OUT.mkdir(exist_ok=True)
(BACK / '.gitignore').write_text('*\n')
class Handler(BaseHTTPRequestHandler):
    chunks = {}
    def do_POST(self):
        name = self.path.lstrip('/')
        if not re.fullmatch(r'[a-z0-9-]+\.json', name): self.send_error(404); return
        size = int(self.headers['Content-Length'])
        if size > 64000000: self.send_error(413); return
        value = json.loads(self.rfile.read(size))
        target = BACK if name.startswith('private-') else OUT
        if isinstance(value, dict) and set(value) == {'Index', 'Total', 'Data'}:
            held = self.chunks.setdefault(name, {})
            held[value['Index']] = value['Data']
            if len(held) < value['Total']:
                self.send_response(200); self.end_headers(); self.wfile.write(b'PART'); return
            value = json.loads(''.join(held[i] for i in range(1, value['Total']+1)))
            del self.chunks[name]
        (target / name).write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')
    def do_GET(self):
        if re.fullmatch(r'/capture/[1-9][0-9]*', self.path):
            raw = (BACK/'private-live-capture.json').read_text(encoding='utf-8')
            index = int(self.path.rsplit('/',1)[1]); count = (len(raw)+399999)//400000
            if index > count: self.send_error(404); return
            value = {'Total':count,'Data':raw[(index-1)*400000:index*400000]}
        elif self.path == '/bundle':
            value = {}
            for f in (ROOT / 'src').rglob('*.luau'):
                if '.server.' in f.name or '.client.' in f.name: continue
                value[f.stem] = re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.(\w+)\)', r'require(script.Parent.\1)', f.read_text(encoding='utf-8-sig'))
        elif self.path.startswith('/private-') and re.fullmatch(r'/private-[a-z0-9-]+\.json', self.path):
            value = json.loads((BACK / self.path.lstrip('/')).read_text())
        else: self.send_error(404); return
        body = json.dumps(value).encode(); self.send_response(200)
        self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(body)
    def log_message(self, fmt, *args): print(fmt % args, flush=True)
print('Execution integrity bridge 127.0.0.1:8798', flush=True)
ThreadingHTTPServer(('127.0.0.1', 8798), Handler).serve_forever()
