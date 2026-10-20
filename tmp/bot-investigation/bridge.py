from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output' / 'bot-investigation-20261014'
OUT.mkdir(parents=True, exist_ok=True)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path not in ('/evidence', '/explanation', '/bx'):
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', 0))
        if not 0 < length < 1000000:
            self.send_error(413)
            return
        value = json.loads(self.rfile.read(length))
        name = {'/evidence': 'live-evidence.json', '/explanation': 'explanation-snapshot.json', '/bx': 'bx-snapshot.json'}[self.path]
        (OUT / name).write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8797), Handler).serve_forever()
