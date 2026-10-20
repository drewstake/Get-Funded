from pathlib import Path
import shutil, subprocess
ROOT=Path(__file__).resolve().parents[1]
subprocess.run(['python',str(ROOT/'tools/prepare_bots_refresh_validation.py')],check=True)
base=ROOT/'tmp/bots-stats';base.mkdir(exist_ok=True)
shutil.copytree(ROOT/'tmp/bots-refresh/candidate',base/'candidate',dirs_exist_ok=True)
shutil.copyfile(ROOT/'tmp/bots-refresh/environment.luau',base/'environment.luau')
runner=(ROOT/'tmp/bots-refresh/regressions.luau').read_text().replace("local names={","local names={'BotStatsTests',").replace('output/bots-refresh-20261015','output/bots-stats-20261015')
(base/'regressions.luau').write_text(runner)
(base/'focused.luau').write_text('''local fs=require('@lune/fs');local serde=require('@lune/serde')
local rows=require('./candidate/BotStatsTests').Run()
for _,r in ipairs(rows)do print(r.Name,r.Passed,r.Detail)end
fs.writeFile('output/bots-stats-20261015/focused-tests.json',serde.encode('json',rows))
local env=require('./environment');local CP=require('./candidate/WorldCheckpoint');local C=require('./candidate/MarketConfig')
local saved=env.game:GetService('HttpService'):JSONDecode(fs.readFile('backups/bots-refresh-20261015/private-checkpoint.json'))
local e,p=CP.Restore(CP.Decode(saved.Record.Checkpoint),C)
local Stats=require('./candidate/BotStats');local at=os.clock();local report=Stats.Text(e,p)
print('Captured report bytes',#report,'Build ms',(os.clock()-at)*1000)
fs.writeFile('backups/bots-stats-20261015/private-captured-report.txt',report)
fs.writeFile('output/bots-stats-20261015/report-size.json',serde.encode('json',{Bytes=#report,Bots=Stats.Capture(e,p).Total.Count}))
''')
