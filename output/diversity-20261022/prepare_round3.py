from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent
variants={'mid-reserve-withdraw':('midquote-mixed','Withdraw'),'mid-reserve-diverse':('midquote-mixed','Mixed'),'last-reserve-diverse':('mixed','Mixed')}
for name,(parent,mode)in variants.items():
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 files['MarketConfig.luau']=files['MarketConfig.luau'].replace('BotDiversity = {Version=1,','BotDiversity = {Version=2,ReserveMode="'+mode+'",')
 p=files['Participants.luau'];p=p.replace('elseif a.Kind=="Reserve"then self:_reserve(a)elseif', 'elseif a.Kind=="Reserve"then if Diversity.Enabled(self,a)then Diversity.Step(self,a)else self:_reserve(a)end elseif')
 files['Participants.luau']=p
 s=files['BotDiversity.luau']
 s=s.replace('function D.Enabled(p,a)',"local function reserveRole(a)\n local index=tonumber(a.Id:match(':(%d+)$'))or 1\n return a.Kind=='Reserve'and index%3==0, index%6==0 and 'Stretch'or 'Portfolio'\nend\nfunction D.Enabled(p,a)")
 s=s.replace("return c and a.PolicyVersion and ((c.Stretch", "return c and a.PolicyVersion and ((c.ReserveMode and reserveRole(a))or(c.Stretch")
 s=s.replace("s.Style=a.Kind=='Reversion'and 'Stretch'or 'Portfolio'", "local assigned,style=reserveRole(a)\n s.Style=assigned and style or a.Kind=='Reversion'and 'Stretch'or 'Portfolio'")
 s=s.replace("if pos then s.Phase='Holding';s.PositionId=pos.Id;s.OpenedAt=e.Time end", "if pos then s.Phase=assigned and 'Reducing'or 'Holding';s.PositionId=pos.Id;s.OpenedAt=e.Time;s.ExitReason=assigned and 'Reallocation'or nil end")
 s=s.replace("local stressed=equity<=a.Budget*(1-p.Config.BotOrderFlow.MaxDrawdown)","local stressed=equity<=a.Budget*(1-p.Config.BotOrderFlow.MaxDrawdown)\n if reserveRole(a)and c.ReserveMode=='Withdraw'then\n  cancelEntries(e,a)\n  if not pos then return end\n  s.Phase='Reducing';s.ExitReason='Reallocation'\n end")
 files['BotDiversity.luau']=s
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(variants);plan['Rounds'].append('round3-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round3-plan.json').write_text(json.dumps({'Basis':'Portfolio alone passes numerical development gates, but BX charts retain quiet runs and jumps. CurrentBX midpoint/mixed has insufficient movement. Reserve has 18 accounts x $5m per market and repeated deep passive supply. Test reassigning six funded accounts per market, without new funding or risk allowance.',
 'Variants':{'mid-reserve-withdraw':'Midpoint/mixed plus one-third Reserve accounts withdraw entry liquidity, gradually settle inherited positions through ordinary matched reduce-only orders, then remain inactive. Supply-only ablation.',
 'mid-reserve-diverse':'Same six accounts settle inherited inventory, then three per market execute independent portfolio mandates and three initiate public stretch fades. Twelve remain passive Reserve providers.',
 'last-reserve-diverse':'Same diverse Reserve allocation with the no-inventory-skew last-execution Maker center, to distinguish midpoint anchoring interaction.'},
 'Safeguards':'Existing funded accounts, budget/limits/margin/risk/recovery and accounting unchanged. New roles use saved identity-derived assignment and private RNG; all entry/exit prices are ordinary funded limit requests. No synthetic price writes, capital injection or synchronized reversal.',
 'Selection':'Only completed development cases used. Independent validation remains unopened. Original gates unchanged.'},indent=2))
print('Frozen',list(variants))
