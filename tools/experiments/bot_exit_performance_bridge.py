import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib, json, re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/bot-exit-performance-20261015'
BACK = ROOT / 'backups/bot-exit-performance-20261015'
OUT.mkdir(exist_ok=True)
BACK.mkdir(exist_ok=True)
(BACK / '.gitignore').write_text('*\n')
PATHS = {
 'ReplicatedStorage.MarketReign.MarketConfig': 'MarketConfig.luau',
 'ServerScriptService.MarketReign.MarketEngine': 'MarketEngine.luau',
 'ServerScriptService.MarketReign.Participants': 'Participants.luau',
 'ServerScriptService.MarketReign.WorldCheckpoint': 'WorldCheckpoint.luau',
 'ServerScriptService.MarketReign.MarketServer': 'MarketServer.server.luau',
 'ServerScriptService.MarketReign.BotExitRetry': 'BotExitRetry.luau',
 'ServerScriptService.MarketReign.SimulationScheduler': 'SimulationScheduler.luau',
 'ServerScriptService.MarketReign.BotExitRetryTests': 'BotExitRetryTests.luau',
 'ServerScriptService.MarketReign.OwnerResetTests': 'OwnerResetTests.luau',
}
def source(path): return path.read_text(encoding='utf-8-sig')
def sha(s): return hashlib.sha256(s.replace('\r\n','\n').encode()).hexdigest()
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path in ('/bundle','/baseline'):
   result={}
   for f in (ROOT/'src').rglob('*.luau'):
    if '.server.' in f.name or '.client.' in f.name: continue
    raw=source(BACK/f.name) if self.path=='/baseline' and (BACK/f.name).exists() else source(f)
    result[f.stem]=re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.([\w]+)\)',r'require(script.Parent.\1)',raw)
  elif self.path=='/release':
   original=json.loads((BACK/'private-studio-sources.json').read_text())['Sources']
   result={p:{'Source':source(source_file(ROOT, n)),'Hash':sha(source(source_file(ROOT, n))),
      'ExpectedHash':sha(original[p]) if p in original else False,
      'ClassName':'Script' if '.server.' in n else 'ModuleScript'} for p,n in PATHS.items()}
  elif self.path=='/checkpoint':result=json.loads((BACK/'private-studio-checkpoint.json').read_text())
  else:self.send_error(404);return
  body=json.dumps(result).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
 def do_POST(self):
  name=self.path.lstrip('/')
  if not re.fullmatch(r'[a-z0-9-]+\.json',name):self.send_error(404);return
  size=int(self.headers['Content-Length'])
  if size>32000000:self.send_error(413);return
  value=json.loads(self.rfile.read(size));target=BACK if name.startswith('private-') else OUT
  (target/name).write_text(json.dumps(value,indent=2),encoding='utf-8')
  self.send_response(200);self.end_headers();self.wfile.write(b'OK')
 def log_message(self,fmt,*args):print(fmt % args,flush=True)
print('Bot exit performance bridge: 127.0.0.1:8797',flush=True)
ThreadingHTTPServer(('127.0.0.1',8797),Handler).serve_forever()
