"""Loopback-only profiler evidence transport. No external account or DataStore access."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, re
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'output/microprofiler-20261027'
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path=='/release':
   m=json.loads((ROOT/'build/place-manifest.json').read_text())
   data=json.dumps([dict(r,source=(ROOT/r['file']).read_text(encoding='utf-8-sig')) for r in m['scripts']]).encode()
  elif self.path.startswith('/script/') and re.fullmatch(r'[a-z-]+\.luau',self.path[8:]):
   data=(ROOT/'tools/experiments/microprofiler'/self.path[8:]).read_bytes()
  else:self.send_error(404);return
  self.send_response(200);self.end_headers();self.wfile.write(data)
 def do_POST(self):
  name=self.path.strip('/');n=int(self.headers.get('Content-Length','0'))
  if not re.fullmatch(r'[a-z0-9-]+\.json',name) or not 0<n<1000000:self.send_error(400);return
  dest=OUT/name
  if dest.exists():self.send_error(409);return
  value=json.loads(self.rfile.read(n));dest.write_text(json.dumps(value),encoding='utf-8')
  self.send_response(200);self.end_headers();self.wfile.write(b'OK')
ThreadingHTTPServer(('127.0.0.1',8820),Handler).serve_forever()
