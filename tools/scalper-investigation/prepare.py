"""Stage current sources for detached scalper diagnostics. No Studio/network writes."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'tmp/scalper-investigation-20261019'
OUT = ROOT / 'output/scalper-investigation-20261019'
MODULES = BASE / 'modules'
MODULES.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT/'tmp/execution-integrity/environment.luau', BASE/'environment.luau')
manifest = {}
for path in (ROOT/'src').glob('*.luau'):
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
    (MODULES/path.name).write_text(text, encoding='utf-8')

source = (MODULES/'Participants.luau').read_text()
start = source.index('function Participants:_scalper(a)')
end = source.index('function Participants:_trader(a)')
scalp = source[start:end]
old = ' local side=signal>0 and 1 or -1'
assert scalp.count(old) == 1
random = scalp.replace(old, ' local side=self.DiagnosticRandom:Next()<0.5 and 1 or -1')
(MODULES/'ParticipantsRandom.luau').write_text(source[:start]+random+source[end:])
ungated = random
gate_start = ungated.index(' local signals=self.Config.BotSignals')
gate_end = ungated.index(' local side=self.DiagnosticRandom')
ungated = ungated[:gate_start]+ungated[gate_end:]
(MODULES/'ParticipantsRandomUnfiltered.luau').write_text(source[:start]+ungated+source[end:])
public = scalp.replace('Signals.Reversal(self,a.Key,window,spread,signals.ScalperDeviationTicks,signals.ReversalTicks)', 'PublicSignals.Reversal(self,a.Key,window,spread,signals.ScalperDeviationTicks,signals.ReversalTicks)')
assert public != scalp
(MODULES/'ParticipantsPublic.luau').write_text('local PublicSignals=require("./BotSignalsPublic")\n'+source[:start]+public+source[end:])
signals = (MODULES/'BotSignals.luau').read_text()
assert signals.count('local fair=population.Markets[key].Fair') == 1
(MODULES/'BotSignalsPublic.luau').write_text(signals.replace('local fair=population.Markets[key].Fair', 'local fair=(window.Low+window.High)/2'))
no_filter = signals.replace('fair-window.Last>=required and ', '').replace('window.Last-fair>=required and ', '')
assert no_filter != signals
(MODULES/'BotSignalsNoFair.luau').write_text(no_filter)
(MODULES/'ParticipantsNoFair.luau').write_text(('local PublicSignals=require("./BotSignalsNoFair")\n'+source[:start]+public+source[end:]))
old_center='(b.Last or b.Reference)*0.83+market.Fair*0.17'
assert source.count(old_center)==1
(MODULES/'ParticipantsFairMaker.luau').write_text(source.replace(old_center,'market.Fair'))
shutil.copyfile(Path(__file__).parent/'run.luau', BASE/'run.luau')
(OUT/'source-manifest.json').write_text(json.dumps(manifest, indent=2))
print('Staged detached sources and diagnostic variants:', BASE)
