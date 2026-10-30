"""Local-only source, asset and validation bridge for the progress page."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path == '/backup':
            target = ROOT / 'backups/progress-redesign-20261001/studio'
            target.mkdir(parents=True, exist_ok=True)
            for name, source in data.items():
                assert name.replace('_', '').replace('.', '').isalnum()
                path = target / (name + '.luau')
                if not path.exists():
                    path.write_text(source, encoding='utf-8')
        elif self.path == '/results':
            (ROOT / 'assets/progress-concepts/validation.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8774), Handler).serve_forever()
