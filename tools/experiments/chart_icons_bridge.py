"""Temporary localhost bridge for chart icon assets, source sync, and Studio backups."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self):
        if self.path not in ('/chart-icons-backup', '/timeframe-icons-backup'):
            self.send_error(404)
            return
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        target = ROOT / ('backups/timeframe-icons-20261001/studio' if self.path == '/timeframe-icons-backup' else 'backups/chart-tool-icons-20261001/studio')
        target.mkdir(parents=True, exist_ok=True)
        for name, source in data.items():
            if name not in ('ChartView', 'TerminalUI'):
                self.send_error(400)
                return
            path = target / (name + '.luau')
            if not path.exists():
                path.write_text(source, encoding='utf-8')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

ThreadingHTTPServer(('127.0.0.1', 8777), Handler).serve_forever()
