"""Make isolated Lune copies; never loads Studio, a DataStore, or the network."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
def prepare(source, name):
    target = ROOT / 'tmp/bot-population' / name
    target.mkdir(parents=True, exist_ok=True)
    for path in source.rglob('*.luau'):
        text = path.read_text(encoding='utf-8-sig')
        text = re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.([\w]+)\)', r'require("./\1")', text)
        text = re.sub(r'local root=script\.Parent', 'local root={}', text)
        text = re.sub(r'require\(root\.([\w]+)\)', r'require("./\1")', text)
        if 'game:' in text or 'Enum.' in text or 'task.' in text:
            text = 'local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n' + text
        if 'Instance.new' in text:
            text = 'local Instance=require("@lune/roblox").Instance\n' + text
        (target/path.name).write_text(text, encoding='utf-8')

prepare(ROOT/'backups/bot-population-20261014/src', 'baseline')
prepare(ROOT/'src', 'proposed')
print('Prepared isolated baseline and proposed modules.')
