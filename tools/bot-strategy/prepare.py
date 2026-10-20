"""Stage the preserved baseline and current candidate for offline comparisons."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'tmp/bot-strategy-20261018'
OUT=ROOT/'output/bot-strategy-20261018'
BASE.mkdir(exist_ok=True);OUT.mkdir(exist_ok=True)
shutil.copyfile(ROOT/'tmp/execution-integrity/environment.luau',BASE/'environment.luau')
for name,source in [('baseline',ROOT/'backups/bot-strategy-20261018/src'),('candidate',ROOT/'src')]:
    target=BASE/name;target.mkdir(exist_ok=True);manifest={}
    for path in source.glob('*.luau'):
        if '.server.' in path.name or '.client.' in path.name:continue
        raw=path.read_text(encoding='utf-8-sig');manifest[path.name]=hashlib.sha256(raw.encode()).hexdigest()
        text=re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.(\w+)\)',r'require("./\1")',raw)
        text=re.sub(r'local root=script\.Parent','local root={}',text)
        text=re.sub(r'require\(root\.(\w+)\)',r'require("./\1")',text)
        if 'game:' in text or 'Enum.' in text or 'task.' in text:text='local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n'+text
        if 'Instance.new' in text:text='local Instance=require("@lune/roblox").Instance\n'+text
        if path.name=='Participants.luau':
            text='local function gate(self,name,a) if self.DiagnosticGate then self:DiagnosticGate(name,a) end end\n'+text
            start=text.index('function Participants:_scalper(a)');end=text.index('function Participants:_trader(a)');scalp=text[start:end]
            substitutions={
                'function Participants:_scalper(a)':'function Participants:_scalper(a)\n gate(self,"Decisions",a)',
                '  if a.PositionId~=p.Id then':'  gate(self,"ManagingPosition",a)\n  if a.PositionId~=p.Id then',
                ' if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end':' if account.Locked or account.Liquidating or b.Spec.CloseOnly then gate(self,"LockedOrRetired",a);e:CancelAll(a.Id,a.Key);return end',
                ' if e.Time<a.ReadyAt or next(account.OpenOrders) then return end':' if e.Time<a.ReadyAt then gate(self,"Cooldown",a);return end\n if next(account.OpenOrders)then gate(self,"WorkingEntry",a);return end',
                ' if not bid or not ask then return end':' if not bid or not ask then gate(self,"MissingQuote",a);return end',
                ' if spread<1 or spread>s.MaxSpreadTicks or spread>=a.Target then return end':' if spread<1 or spread>s.MaxSpreadTicks or spread>=a.Target then gate(self,"Spread",a);return end',
                ' if math.abs(signal)<(a.EntryThreshold or .2) then return end':' if math.abs(signal)<(a.EntryThreshold or .2) then gate(self,"Signal",a);return end',
                ' local size=self:_fit(a,side,a.Size);if size<1 then return end':' local size=self:_fit(a,side,a.Size);if size<1 then gate(self,"Capacity",a);return end\n gate(self,"EntrySubmit",a)',
            }
            if name=='baseline':substitutions[' if policy and math.abs(last-previous)<math.max(a.MinMove,spread+s.MaxSlippageTicks+a.EntryBuffer)then return end']=' if policy and math.abs(last-previous)<math.max(a.MinMove,spread+s.MaxSlippageTicks+a.EntryBuffer)then gate(self,"MinMove",a);return end'
            else:
                substitutions.update({
                    '  if a.Target<spread+s.MaxSlippageTicks+signals.ScalperProfitBufferTicks then return end':'  if a.Target<spread+s.MaxSlippageTicks+signals.ScalperProfitBufferTicks then gate(self,"TargetCosts",a);return end',
                    '  if not window then return end':'  if not window then gate(self,"Warmup",a);return end',
                    '   if not side then return end':'   if not side then gate(self,"Reversal",a);return end',
                    '   if math.abs(window.Move)<required or window.Move*window.RecentMove<0 then return end':'   if math.abs(window.Move)<required then gate(self,"MinMove",a);return end\n   if window.Move*window.RecentMove<0 then gate(self,"MomentumConfirmation",a);return end',
                })
            for old,new in substitutions.items():
                assert scalp.count(old)==1,(name,old,scalp.count(old));scalp=scalp.replace(old,new)
            text=text[:start]+scalp+text[end:]
        (target/path.name).write_text(text,encoding='utf-8')
    (OUT/(name+'-manifest.json')).write_text(json.dumps(manifest,indent=2))
    runner=(ROOT/'tools/bot-diagnostics/run.luau').read_text().replace('./modules/','./'+name+'/').replace('output/bot-diagnostics-20261018/','output/bot-strategy-20261018/')
    runner=runner.replace("local variant=process.args[3]or 'baseline'","local variant=process.args[3]or '"+name+"'")
    runner=runner.replace('AllScalpersFlat=0,AnyScalperOrders=0','AllScalpersFlat=0,AllScalpersIdle=0,AnyScalperOrders=0')
    runner=runner.replace('if flat then samples.AllScalpersFlat+=1 end;','if flat then samples.AllScalpersFlat+=1;if not orders then samples.AllScalpersIdle+=1 end end;')
    (BASE/(name+'.luau')).write_text(runner,encoding='utf-8')
for path in Path(__file__).parent.glob('*.luau'):shutil.copyfile(path,BASE/path.name)
print('Prepared baseline/candidate; no network or saved-world writes.')
