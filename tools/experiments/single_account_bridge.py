"""Local-only source/fixture bridge. Does not access Roblox persistence."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[2]
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT), **kw)
    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path == '/backup':
            target = ROOT / 'backups/single-account-20261001/studio'
            target.mkdir(parents=True, exist_ok=True)
            for name, source in data.items():
                assert name.replace('_', '').replace('.', '').isalnum()
                path = target / (name + '.luau')
                if not path.exists(): path.write_text(source, encoding='utf-8')
        elif self.path.startswith('/results/'):
            name = self.path.rsplit('/', 1)[-1]
            assert name.replace('-', '').replace('.', '').isalnum()
            target = ROOT / 'output/single-account-20261001'
            target.mkdir(parents=True, exist_ok=True)
            (target / name).write_text(json.dumps(data, indent=2), encoding='utf-8')
        else:
            self.send_error(404); return
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')
ThreadingHTTPServer(('127.0.0.1', 8771), Handler).serve_forever()
