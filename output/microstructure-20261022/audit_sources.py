from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent
allowed={'Participants.luau','WorldCheckpoint.luau','BotMomentum.luau','BotWhale.luau','MarketConfig.luau'}
out={}
for d in sorted((R/'variants').iterdir()):
 files=[];patch=[];manifest=json.loads((d/'manifest.json').read_text())
 for name,h in manifest.items():
  assert name in allowed,(d,name)
  src=(d/name).read_text(encoding='utf8');assert hashlib.sha256(src.encode()).hexdigest()==h,(d,name,'freeze changed')
  base=R/'original'/('shared'if name=='MarketConfig.luau'else'server')/name
  diff=list(difflib.unified_diff(base.read_text(encoding='utf8').splitlines(True),src.splitlines(True),fromfile='original/'+name,tofile=d.name+'/'+name))
  patch+=diff;files.append({'File':name,'SHA256':h,'DiffLines':len(diff)})
 (d/'change.patch').write_text(''.join(patch),encoding='utf8')
 out[d.name]={'Files':files,'PreservedModules':['MarketEngine','PlayerExecution','ProtectiveOrders','BotParticipation','BotExitRetry','TradeProtection','ContractLimits','BotPopulation','WorldService'],'SnapshotBarrier':29}
(R/'source-scope-audit.json').write_text(json.dumps(out,indent=2))
p=R/'experiment.json';plan=json.loads(p.read_text())
if not(R/'experiment-round1.json').exists():(R/'experiment-round1.json').write_text(p.read_text())
plan['Candidates']=list(out);plan['Rounds']=['experiment-round1.json']+[f'round{i}-plan.json'for i in range(2,7)]
p.write_text(json.dumps(plan,indent=2))
print('Verified frozen manifests and generated patches for',len(out),'variants')
