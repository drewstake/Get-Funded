from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/help-redesign-20261015'
BACK = ROOT / 'backups/help-redesign-20261015'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        routes = {
            '/source': ROOT / 'src/TerminalUI.luau',
            '/before': BACK / 'TerminalUI.luau',
            '/validate': ROOT / 'tools/ValidateHelpRedesign.luau',
            '/install': OUT / 'InstallHelpRedesign.luau',
        }
        path = routes.get(self.path)
        if not path or not path.exists():
            self.send_error(404); return
        data = path.read_bytes()
        self.send_response(200); self.end_headers(); self.wfile.write(data)

    def do_POST(self):
        paths = {'/capture': BACK / 'studio.json', '/results': OUT / 'validation.json', '/installed': OUT / 'installed.json'}
        path = paths.get(self.path)
        if not path:
            self.send_error(404); return
        value = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        path.write_text(json.dumps(value, indent=2), encoding='utf-8')
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8803), Handler).serve_forever()
