from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
R=Path(__file__).resolve().parent
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(R),**kwargs)
 def do_POST(self):
  target=(R/self.path.lstrip('/')).resolve()
  if not target.is_relative_to(R):self.send_error(400);return
  target.parent.mkdir(parents=True,exist_ok=True)
  target.write_bytes(self.rfile.read(int(self.headers['Content-Length'])))
  self.send_response(200);self.end_headers();self.wfile.write(b'OK')
ThreadingHTTPServer(('127.0.0.1',8833),Handler).serve_forever()
