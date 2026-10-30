"""Stage preserved baseline/current sources for isolated, reproducible validation."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'tmp/order-driven-market-20261019'
OUT = ROOT / 'output/order-driven-market-20261019'
BASE.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT/'tmp/execution-integrity/environment.luau', BASE/'environment.luau')
for name, source in [('baseline', ROOT/'backups/order-driven-market-20261019/src'), ('candidate', ROOT/'src')]:
    target = BASE/name
    target.mkdir(exist_ok=True)
    manifest = {}
    for path in source.rglob('*.luau'):
        if '.server.' in path.name or '.client.' in path.name:
            continue
        raw = path.read_text(encoding='utf-8-sig')
        manifest[path.name] = hashlib.sha256(raw.encode()).hexdigest()
        text = re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.(\w+)\)', r'require("./\1")', raw)
        text = re.sub(r'local root=script\.Parent', 'local root={}', text)
        text = re.sub(r'require\(root\.(\w+)\)', r'require("./\1")', text)
        if 'game:' in text or 'Enum.' in text or 'task.' in text:
            text = 'local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n'+text
        if 'Instance.new' in text:
            text = 'local Instance=require("@lune/roblox").Instance\n'+text
        (target/path.name).write_text(text, encoding='utf-8')
    (OUT/(name+'-manifest.json')).write_text(json.dumps(manifest, indent=2))
for path in Path(__file__).parent.rglob('*.luau'):
    shutil.copyfile(path, BASE/path.name)
print('Prepared detached baseline and candidate.')
