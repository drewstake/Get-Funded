from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;P=R.parent/'microstructure-20261022/variants/no-skew-sparse-whale'
base={p.name:p.read_text(encoding='utf8')for p in P.glob('*.luau')}
module=(R/'BotDiversity.luau').read_text(encoding='utf8')
variants={'control':None,'stretch':(True,False,False),'portfolio':(False,True,False),'mixed':(True,True,False),'mixed-wide':(True,True,True)}
for name,settings in variants.items():
 files=dict(base);files['WorldCheckpoint.luau']=files['WorldCheckpoint.luau'].replace('Version=29,Readable={[29]=true,','Version=30,Readable={[30]=true,')
 if settings:
  stretch,portfolio,wide=settings
  horizons='{{60,150},{150,360},{360,720}}'if wide else '{{40,90},{90,180},{180,420}}'
  config=f''' BotDiversity = {{Version=1,Stretch={str(stretch).lower()},Portfolio={str(portfolio).lower()},
  Horizons={horizons},ExtensionFraction={{.0003,.0008}},TakeFraction={{.25,.6}},
  HoldSeconds={{70,240}},BuildSeconds={{12,40}},TargetFraction={{.35,.7}},CooldownSeconds={{40,140}},
  StartDelay={{3,90}},SliceSeconds={{3,9}},SliceFraction={{.7,1}},StopCooldownMultiple={{2,4}},
  PositionRiskFraction=.025,MaxSlippageTicks=3,MinExtensionTicks=8,MinProfitTicks=6,ProfitBufferTicks=2,MaxSpreadTicks=12}},
'''
  files['MarketConfig.luau']=files['MarketConfig.luau'].replace(' BotInformationVersion',config+' BotInformationVersion')
  p=files['Participants.luau'].replace('local Participants={}','local Participants={}\nlocal Diversity=require(script.Parent.BotDiversity)')
  p=p.replace(' if Pressure.Enabled(self,a)then',' if Diversity.Enabled(self,a)then Diversity.Step(self,a);return end\n if Pressure.Enabled(self,a)then')
  p=p.replace('   if repairing then delay=',"   if Diversity.Enabled(self,a) and a.DiversityNext then delay=math.max(self.Config.StepSeconds,a.DiversityNext-e.Time)end\n   if repairing then delay=")
  files['Participants.luau']=p;files['BotDiversity.luau']=module
  cp=files['WorldCheckpoint.luau']
  cp=cp.replace(' local whale=currentConfig.BotWhale'," local diversity=currentConfig.BotDiversity and currentConfig.BotDiversity.Version or 0\n local savedDiversity=config.BotDiversity and config.BotDiversity.Version or 0\n assert(savedDiversity<=diversity,'Cannot downgrade trader diversity policy')\n if savedDiversity<diversity then config.BotDiversity=clone(currentConfig.BotDiversity)end\n local whale=currentConfig.BotWhale")
  files['WorldCheckpoint.luau']=cp
 d=R/'variants'/name;d.mkdir(exist_ok=False)
 patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8')
  old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']=list(variants);(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round1-plan.json').write_text(json.dumps({'Basis':'Existing no-skew/sparse/Whale control removes Maker reservation displacement but misses pullbacks and useful movement. Prior Reversion waits for turn/slowing. Test proactive heterogeneous stretch fades and independent portfolio demand using existing funded groups, separately then crossed.',
 'Variants':{'control':'Previous no-skew-sparse-whale mechanism unchanged; experimental CP30 barrier only','stretch':'Reversion accounts adopt public-window stretch fades before turn, with finite staged entry, risk cap, staggered horizons and profit/time exits','portfolio':'Value accounts adopt independent signed finite portfolio mandates with staged entry and time exits; no shared direction or last-price signal','mixed':'Both independently tested styles on the same book','mixed-wide':'Same combination but broader countertrend horizons'},
 'Funding':'All existing bot identities, a.Kind, allocations, cash, limits and population counts preserved. Behavioral subtypes use dedicated saved state; no added accounts or capital.',
 'Safety':'Exact replay each run; restore preserves Engine/Population. News off. Stops, pauses and manual protections retain authority.',
 'Gates':'Unchanged from prior investigation; unused holdouts not opened.'},indent=2))
print('Frozen',list(variants))
