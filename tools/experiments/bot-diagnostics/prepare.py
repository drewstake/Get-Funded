"""Stage current modules for a detached, network-free bot investigation."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'tmp/bot-diagnostics-20261018'
OUT = ROOT / 'output/bot-diagnostics-20261018'
(BASE / 'modules').mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / 'tmp/execution-integrity/environment.luau', BASE / 'environment.luau')
manifest = {}
for path in (ROOT / 'src').rglob('*.luau'):
    if '.server.' in path.name or '.client.' in path.name:
        continue
    raw = path.read_text(encoding='utf-8-sig')
    manifest[path.name] = hashlib.sha256(raw.encode()).hexdigest()
    text = re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.(\w+)\)', r'require("./\1")', raw)
    text = re.sub(r'local root=script\.Parent', 'local root={}', text)
    text = re.sub(r'require\(root\.(\w+)\)', r'require("./\1")', text)
    if 'game:' in text or 'Enum.' in text or 'task.' in text:
        text = 'local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n' + text
    if 'Instance.new' in text:
        text = 'local Instance=require("@lune/roblox").Instance\n' + text
    if path.name == 'Participants.luau':
        text = 'local function gate(self,name,a) if self.DiagnosticGate then self:DiagnosticGate(name,a) end end\n' + text
        begin = text.index('function Participants:_scalper(a)')
        end = text.index('function Participants:_trader(a)')
        scalp = text[begin:end]
        substitutions = {
            'function Participants:_scalper(a)': 'function Participants:_scalper(a)\n gate(self,"Decisions",a)',
            '  if a.PositionId~=p.Id then': '  gate(self,"ManagingPosition",a)\n  if a.PositionId~=p.Id then',
            ' if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end': ' if account.Locked or account.Liquidating or b.Spec.CloseOnly then gate(self,"LockedOrRetired",a);e:CancelAll(a.Id,a.Key);return end',
            ' if e.Time<a.ReadyAt or next(account.OpenOrders) then return end': ' if e.Time<a.ReadyAt then gate(self,"Cooldown",a);return end\n if next(account.OpenOrders) then gate(self,"WorkingEntry",a);return end',
            ' if not bid or not ask then return end': ' if not bid or not ask then gate(self,"MissingQuote",a);return end',
            ' if spread<1 or spread>s.MaxSpreadTicks or spread>=a.Target then return end': ' if spread<1 or spread>s.MaxSpreadTicks or spread>=a.Target then gate(self,"Spread",a);return end',
            ' if policy and math.abs(last-previous)<math.max(a.MinMove,spread+s.MaxSlippageTicks+a.EntryBuffer)then return end': ' if policy and math.abs(last-previous)<math.max(a.MinMove,spread+s.MaxSlippageTicks+a.EntryBuffer)then gate(self,"MinMove",a);return end',
            ' if math.abs(signal)<(a.EntryThreshold or .2) then return end': ' if math.abs(signal)<(a.EntryThreshold or .2) then gate(self,"Signal",a);return end',
            ' local size=self:_fit(a,side,a.Size);if size<1 then return end': ' local size=self:_fit(a,side,a.Size);if size<1 then gate(self,"Capacity",a);return end\n gate(self,"EntrySubmit",a)',
        }
        for old, new in substitutions.items():
            assert scalp.count(old) == 1, (old, scalp.count(old))
            scalp = scalp.replace(old, new)
        text = text[:begin] + scalp + text[end:]
    (BASE / 'modules' / path.name).write_text(text, encoding='utf-8')
    if path.name == 'Participants.luau':
        old='local signal=a.Bias+r:Noise()*1.3-inventory/a.Limit*1.8'
        new='local signal=a.Bias+r:Noise()*((a.Kind=="Protective"or a.Kind=="Reversion")and .2 or 1.3)-inventory/a.Limit*1.8'
        assert text.count(old)==1
        (BASE / 'modules' / 'ParticipantsLowerNoise.luau').write_text(text.replace(old,new),encoding='utf-8')
        old='signal-=momentum*r:Range(0.6,1.6) signal+=edge*0.3'
        assert text.count(old)==1
        (BASE / 'modules' / 'ParticipantsNoFade.luau').write_text(text.replace(old,'signal-=momentum*r:Range(0.6,1.6)*0 signal+=edge*0.3'),encoding='utf-8')
for path in Path(__file__).parent.rglob('*.luau'):
    shutil.copyfile(path, BASE / path.name)
(OUT / 'source-manifest.json').write_text(json.dumps(manifest, indent=2))
print('Prepared detached modules. Game sources and saved worlds are unchanged.')
