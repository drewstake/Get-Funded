"""Build detached baseline/candidate modules for Lune, without Studio or network."""
from pathlib import Path
import re, shutil
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'tmp/execution-integrity'
BASE.mkdir(exist_ok=True)
for runner in (ROOT/'tools/execution-integrity').glob('*.luau'):
    shutil.copyfile(runner, BASE/runner.name)
for name, source in [('baseline', ROOT/'backups/execution-integrity-20261015/src'), ('candidate', ROOT/'src')]:
    target = BASE/name; target.mkdir(exist_ok=True)
    for path in source.glob('*.luau'):
        text = path.read_text(encoding='utf-8-sig')
        text = re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.(\w+)\)', r'require("./\1")', text)
        text = re.sub(r'local root=script\.Parent', 'local root={}', text)
        text = re.sub(r'require\(root\.(\w+)\)', r'require("./\1")', text)
        if 'game:' in text or 'Enum.' in text or 'task.' in text:
            text = 'local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n'+text
        if 'Instance.new' in text: text = 'local Instance=require("@lune/roblox").Instance\n'+text
        (target/path.name).write_text(text, encoding='utf-8')
print('Prepared detached execution integrity modules.')
