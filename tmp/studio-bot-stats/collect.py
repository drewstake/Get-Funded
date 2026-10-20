from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, re

OUT = Path(__file__).resolve().parents[2] / 'output/studio-bot-stats-20261015'
OUT.mkdir(parents=True, exist_ok=True)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        name = self.path.lstrip('/')
        if not re.fullmatch(r'studio-bot-stats-[a-z]+\.json', name):
            self.send_error(404); return
        value = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        (OUT / name).write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')
    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

print('Studio stats collector on 127.0.0.1:8796', flush=True)
ThreadingHTTPServer(('127.0.0.1', 8796), Handler).serve_forever()
