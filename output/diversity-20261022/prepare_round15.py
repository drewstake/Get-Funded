from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent
arms={'rolling-cost-aware':False,'rolling-touch-participation':True}
parent='rolling-portfolio-depth'
helper='''function D.EntrySize(p,a,side,size)
 local e,c=p.Engine,p.Config.BotDiversity;local guard=c.AllocationExecution
 if not guard then return size end
 local b=e.Books[a.Key];local bid,ask=e:PublicPrices(a.Key)
 if not bid or not ask then return 0 end
 -- Pay no more than a bounded part of the existing stop-risk allowance to enter.
 if (ask-bid)/b.Spec.Tick+c.MaxSlippageTicks>a.Stop*guard.StopCostFraction then return 0 end
 if guard.TouchFraction then
  local depth=e:PublicDepth(a.Key,1);local levels=if side==1 then depth.Asks else depth.Bids
  local touch=levels[1];if not touch then return 0 end
  size=math.min(size,math.floor(touch.Quantity*guard.TouchFraction))
 end
 return size
end
'''
tests=''' if C.BotDiversity.AllocationExecution then
  test('Allocation entry waits on wide or one-sided quotes without spending capital',function()
   for _,side in ipairs({1,-1})do
    local e,p,a,b,s=fixture('Value');e:AdvanceClock(100)
    quote(e,b,1,1000,b.Reference-20);quote(e,b,-1,1000,b.Reference+20)
    s.Phase='Allocating';s.Target=side*10;s.EpisodeUntil=e.Time+1000;s.ReviewAt=e.Time+500
    local orders=e.NextOrder;local balance=e.Accounts[a.Id].Balance;D.Step(p,a)
    assert(e.NextOrder==orders and e.TotalVolume==0 and e.Accounts[a.Id].Balance==balance)
    e:CancelAll(side==1 and 'buyer' or 'seller');D.Step(p,a);assert(e.NextOrder==orders);e:Audit()
   end
  end)
  test('Allocation cost guard does not block funded risk reductions',function()
   local e,p,a,b,s=fixture('Value');e:AdvanceClock(100)
   quote(e,b,1,1000);quote(e,b,-1,1000);D.Step(p,a)
   local pos=assert(e.Accounts[a.Id].Positions.BX);local qty=pos.Quantity
   e:CancelAll('buyer');e:CancelAll('seller')
   -- Touch remains at the current mark; the same-side quote is far away.
   quote(e,b,-pos.Direction,1000,b.Last)
   quote(e,b,pos.Direction,1000,b.Last-pos.Direction*20)
   local volume=e.TotalVolume;s.EpisodeUntil=e.Time;D.Step(p,a)
   assert(e.TotalVolume==volume+qty and not e.Accounts[a.Id].Positions.BX);e:Audit()
  end)
  if C.BotDiversity.AllocationExecution.TouchFraction then
   test('Allocation child leaves real opposite touch depth and waits below one contract',function()
    for _,side in ipairs({1,-1})do
     local e,p,a,b,s=fixture('Value');e:AdvanceClock(100)
     quote(e,b,1,8);quote(e,b,-1,8)
     s.Phase='Allocating';s.Target=side*10;s.EpisodeUntil=e.Time+1000;s.ReviewAt=e.Time+500
     D.Step(p,a);local pos=assert(e.Accounts[a.Id].Positions.BX)
     assert(pos.Quantity==2 and e.TotalVolume==2)
     e:CancelAll('buyer');e:CancelAll('seller');quote(e,b,1,3);quote(e,b,-1,3)
     local volume=e.TotalVolume;D.Step(p,a);assert(e.TotalVolume==volume);e:Audit()
    end
   end)
  end
 end
'''
for name,participation in arms.items():
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 s=files['MarketConfig.luau'];assert s.count('BotDiversity = {Version=4,')==1
 files['MarketConfig.luau']=s.replace('BotDiversity = {Version=4,','BotDiversity = {Version=5,AllocationExecution={StopCostFraction=.25'+(',TouchFraction=.25'if participation else'')+'},')
 s=files['BotDiversity.luau'];assert s.count('function D.Allocate(p,a,s)')==1
 s=s.replace('function D.Allocate(p,a,s)',helper+'function D.Allocate(p,a,s)')
 needle=' else size=p:_fit(a,side,size)end\n if size<1 then return end'
 assert s.count(needle)==1
 s=s.replace(needle,' else size=p:_fit(a,side,size);size=D.EntrySize(p,a,side,size)end\n if size<1 then return end')
 files['BotDiversity.luau']=s
 s=files['BotDiversityTests.luau'];needle=" test('Private independent profiles are diverse, persistent and do not draw shared RNG',function()";assert s.count(needle)==1
 files['BotDiversityTests.luau']=s.replace(needle,tests+needle)
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
 (d/'integration.json').write_text(json.dumps({'Parent':parent,'Checkpoint':31,'Change':'Bound rolling risk-entry spread plus allowed slippage to 25% of existing stop distance. Reductions remain unrestricted by this guard.'+(' Also bound child quantity to 25% of existing opposite touch, rounded down.'if participation else'')},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(arms);plan['Rounds'].append('round15-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round15-plan.json').write_text(json.dumps({'Basis':'Both original-depth rolling arms fix spread but fail recovery and missing quotes. Missing quotes concentrate in BT; rolling allocation risk entry currently has no spread or available-depth check, unlike Stretch signal entry. This is a code observation, not yet a causal attribution. Current portfolio-depth recovery is $8.204m; the patient derivative $8.335m and it also fails current BX shape.',
 'Parent':parent,'Variants':arms,'Hypothesis':'A bounded execution-cost budget can stop discretionary risk entry from buying depleted books. The second arm isolates whether touch participation helps beyond the cost budget. Keep target process, timers, per-account capital, maximum size and all other strategies unchanged. Never delay mandatory or voluntary risk reductions on this new guard.',
 'Selection':'All existing paired six-case gates and candle review unchanged. Holdouts remain ungenerated. No parameter grid or validation reuse.'},indent=2));print('Frozen',list(arms))
