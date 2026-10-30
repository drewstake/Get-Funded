"""Build detached Luau modules; uses the existing network-denying Lune environment."""
from pathlib import Path
import re, shutil
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'tmp/bots-refresh'
(BASE/'candidate').mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT/'tools/execution-integrity/environment.luau', BASE/'environment.luau')
for p in (ROOT/'src').rglob('*.luau'):
    text = p.read_text(encoding='utf-8-sig')
    text = re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.(\w+)\)', r'require("./\1")', text)
    text = re.sub(r'local root=script\.Parent', 'local root={}', text)
    text = re.sub(r'require\(root\.(\w+)\)', r'require("./\1")', text)
    if 'game:' in text or 'Enum.' in text or 'task.' in text:
        text = 'local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n'+text
    if 'Instance.new' in text: text = 'local Instance=require("@lune/roblox").Instance\n'+text
    (BASE/'candidate'/p.name).write_text(text, encoding='utf-8')
runner = (ROOT/'tools/execution-integrity/regressions.luau').read_text()
runner = runner.replace("local names={", "local names={'BotRefreshTests',").replace('output/execution-integrity-20261015/', 'output/bots-refresh-20261015/')
(BASE/'regressions.luau').write_text(runner)
(BASE/'focused.luau').write_text('local r=require("./candidate/BotRefreshTests").Run(); for _,row in ipairs(r)do print(row.Name,row.Passed,row.Detail)end')
(BASE/'captured.luau').write_text('''local fs=require('@lune/fs');local serde=require('@lune/serde');local env=require('./environment')
local saved=env.game:GetService('HttpService'):JSONDecode(fs.readFile('backups/bots-refresh-20261015/private-checkpoint.json'))
local snapshot=require('./candidate/WorldCheckpoint').Decode(saved.Record.Checkpoint)
local result=require('./candidate/BotRefreshTests').Captured(snapshot,128)
fs.writeFile('output/bots-refresh-20261015/captured-replay.json',serde.encode('json',result))
print(serde.encode('json',result))
''')
