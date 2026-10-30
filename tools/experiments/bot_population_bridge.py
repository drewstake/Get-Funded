"""Loopback-only bridge for isolated Studio tests. No DataStore writes or game sync."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/bot-population-20261014'
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ['/proposed','/baseline']:
            self.send_error(404);return
        source=ROOT/('src' if self.path=='/proposed' else 'backups/bot-population-20261014/src')
        bundle={}
        for f in source.rglob('*.luau'):
            if '.server.' in f.name or '.client.' in f.name:continue
            s=f.read_text(encoding='utf-8-sig')
            s=re.sub(r'require\(game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign\.([\w]+)\)',r'require(script.Parent.\1)',s)
            bundle[f.stem]=s
        bundle['BotPopulationExperiment']=(ROOT/'tools/experiments/BotPopulationExperiment.luau').read_text()
        bundle['DryRunBotPopulation']=(ROOT/'tools/studio/DryRunBotPopulation.luau').read_text()
        bundle['BenchmarkBotPopulation']=(ROOT/'tools/studio/BenchmarkBotPopulation.luau').read_text()
        body=json.dumps(bundle).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
    def do_POST(self):
        name=self.path.lstrip('/')
        if not re.fullmatch(r'[a-z0-9-]+\.json',name):self.send_error(404);return
        size=int(self.headers.get('Content-Length','0'))
        if size>32000000:self.send_error(413);return
        data=json.loads(self.rfile.read(size));OUT.mkdir(exist_ok=True)
        (OUT/name).write_text(json.dumps(data,indent=2))
        self.send_response(200);self.end_headers();self.wfile.write(b'OK')
    def log_message(self,fmt,*args):print(fmt%args,flush=True)
print('Bot validation bridge listening on 127.0.0.1:8798',flush=True)
ThreadingHTTPServer(('127.0.0.1',8798),Handler).serve_forever()
