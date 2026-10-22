from pathlib import Path
import json,hashlib,difflib,sys
R=Path(__file__).resolve().parent;parent=sys.argv[1];name=sys.argv[2]if len(sys.argv)>2 else parent+'-ready'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
s=files['BotDiversity.luau'];assert s.count('return c and a.PolicyVersion')==1
files['BotDiversity.luau']=s.replace('return c and a.PolicyVersion','return c and p.Config.BotOrderFlow and p.Config.BotPopulation and p.Config.BotMomentum and a.PolicyVersion')
s=files['BotWhale.luau'];assert s.count('random(s)<.30+urgency*(.65-.30)')==1
files['BotWhale.luau']=s.replace('random(s)<.30+urgency*(.65-.30)','random(s)<c.AggressiveProbability[1]+urgency*(c.AggressiveProbability[2]-c.AggressiveProbability[1])')
s=files['BotWhale.luau'];needle='local ownTouch=s.Side==1 and bid or ask;local opposite=s.Side==1 and ask or bid';assert needle in s
s=s.replace(needle,'local ownTouch=if s.Side==1 then bid else ask;local opposite=if s.Side==1 then ask else bid')
s=s.replace('local touch=aggressive and opposite or ownTouch','local touch=if aggressive then opposite else ownTouch')
files['BotWhale.luau']=s
files['BotDiversity.luau']=files['BotDiversity.luau'].replace('local touch=side==1 and ask or bid','local touch=if side==1 then ask else bid').replace('local touch=pos.Direction==1 and bid or ask','local touch=if pos.Direction==1 then bid else ask')
s=files['MarketConfig.luau'];assert s.count('AggressiveProbability={.10,.35}')==1
files['MarketConfig.luau']=s.replace('AggressiveProbability={.10,.35}','AggressiveProbability={.30,.65}')
s=files['WorldCheckpoint.luau'];assert s.count('Version=30,Readable={[30]=true,')==1
s=s.replace('Version=30,Readable={[30]=true,','Version=31,Readable={[31]=true,')
needle='if savedWhale<whale then config.BotWhale=clone(currentConfig.BotWhale)end';assert s.count(needle)==1
s=s.replace(needle,needle+'\n -- Execution aggressiveness is build policy; preserve saved version-1 profiles, clocks and RNG.\n if config.BotWhale and currentConfig.BotWhale then config.BotWhale.AggressiveProbability=clone(currentConfig.BotWhale.AggressiveProbability)end')
files['WorldCheckpoint.luau']=s
files['Participants.luau']=files['Participants.luau'].replace("-- Quotes follow actual executions; inventory skews each maker's own reservation price.","-- Quote prices follow executions without recurrent inventory displacement; inventory affects funded quantities.")
for test in ['BotOrderFlowTests','BotParticipationTests','OrderFlowMarketTests','BotWhaleTests','BotRefreshTests']:
 s=(R/'original/server'/(test+'.luau')).read_text(encoding='utf8');assert 'CP.Version==28'in s
 files[test+'.luau']=s.replace('CP.Version==28','CP.Version==31')
s=files['BotWhaleTests.luau'];needle=" local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end";assert needle in s
files['BotWhaleTests.luau']=s.replace(needle,needle+'\n'+(R/'quote-safety-cases.luau').read_text(encoding='utf8'))
s=(R/'original/server/BotSignalsTests.luau').read_text(encoding='utf8');needle='local e=E.new(clone(C),73521);local p=P.new(e)';assert needle in s
files['BotSignalsTests.luau']=s.replace(needle,"-- Retained legacy turn-confirmation strategy; new stretch behavior has its own suite.\n local c=clone(C);c.BotDiversity=nil;local e=E.new(c,73521);local p=P.new(e)")
needle='if lane==1 then offset=math.max(1,math.round(offset/3))end'
if needle in files['Participants.luau']:
 files['Participants.luau']=files['Participants.luau'].replace(needle,'if lane==1 and lanes.InnerOffsetDivisor then offset=math.max(1,math.round(offset/lanes.InnerOffsetDivisor))end')
 files['MarketConfig.luau']=files['MarketConfig.luau'].replace('MakerLanes = {Count=20,','MakerLanes = {Count=20,InnerOffsetDivisor=3,')
 s=(R/'original/server/MakerLiquidityTests.luau').read_text(encoding='utf8')
 needle='local c=clone(C);local e=E.new(c,891)';assert s.count(needle)==1
 s=s.replace(needle,'local c=clone(C);c.MakerLanes.InnerOffsetDivisor=nil;local e=E.new(c,891)')
 needle=' test("Old worlds adopt tuning without altering accounts, tape or resting orders during restore",function()';assert needle in s
 s=s.replace(needle,'''
 test("Nearest neighboring lane bridges depletion while the distant funded ladder remains",function()
  local c=clone(C);local e=E.new(c,891)
  local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(891),Agents={},Markets={},Regime={Volatility=1,Liquidity=1,Activity=1}},P)
  local inner={BX=2,BT=6,BG=2}
  for _,key in ipairs(c.ContractOrder)do
   p.Markets[key]={};local first={}
   for i=1,c.MakerLanes.Count do
    local a=p:_agent(key,'Maker',i);local cash=e.Accounts[a.Id].Balance;local state=p.Random.State;p:_maker(a)
    assert(e.Accounts[a.Id].Balance==cash and p.Random.State==state)
    for _,side in ipairs({1,-1})do
     local price=assert(e.Orders[a.Quotes[tostring(side)..':1']]).Price
     if i==1 then first[side]=price
     else local distance=(first[side]-price)*side
      if i==2 then assert(distance==inner[key])else assert(distance==(i-1)*c.MakerLanes.SpacingTicks[key])end
     end
    end
   end
   assert(e.TotalVolume==0 and e.Books[key].Last==nil)
  end
  e:Audit()
 end)
'''+needle)
 files['MakerLiquidityTests.luau']=s
s=(R/'BotDiversityTests.luau').read_text(encoding='utf8');needle=' local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and\'Passed\'or tostring(r)})end';assert needle in s
s=s.replace(needle,needle+'''
 test('Legacy policy configurations cannot accidentally enable diversity',function()
  for _,key in ipairs({'BotOrderFlow','BotPopulation','BotMomentum'})do
   local e,p,a,b,s=fixture();p.Config[key]=nil;assert(not D.Enabled(p,a));D.Step(p,a);assert(e.TotalVolume==0)
  end
 end)
 test('Execution-policy migration retains every saved Whale profile and economic state',function()
  local old=copy(C);old.BotWhale.AggressiveProbability={.10,.35};local e=E.new(old,7919);local p=P.new(e)
  for _=1,80 do p:Step()end
  local before=CP.Capture(e,p);local re,rp=CP.Restore(before,C);local after=CP.Capture(re,rp)
  equal(before.Engine,after.Engine);equal(before.Population,after.Population)
  equal(re.Config.BotWhale.AggressiveProbability,C.BotWhale.AggressiveProbability)
  assert(re.Config.BotWhale.Version==old.BotWhale.Version)
 end)
''')
files['BotDiversityTests.luau']=s
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
(d/'integration.json').write_text(json.dumps({'Parent':parent,'Purpose':'Configuration compatibility and versioned integration; default economic trajectories must match parent before promotion.','Checkpoint':31,'ReadableResearchCheckpoints':False,'Changes':['Diversity guard when legacy policy dependencies are absent','Whale aggressiveness honors configuration; default .30-.65 as parent, migrated without new profiles','Legacy Reversion tests explicitly disable new strategy; old assertions retained','Checkpoint assertions updated; new migration/dependency coverage']},indent=2))
print('Frozen integration derivative',name)
