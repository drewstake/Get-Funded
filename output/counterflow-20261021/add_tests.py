from pathlib import Path
R=Path(__file__).resolve().parent
extra='''
 test('Profit exits are symmetric and use funded reduce-only fills',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,s=fixture();history(e,p,b,side);M.Step(p,a)
   local ac=e.Accounts[a.Id];local pos=assert(ac.Positions.BX);local entry=pos.Entry/b.Spec.Tick
   s.Phase='Holding';s.NextReview=e.Time+1000;s.ProfitAge=0;s.ProfitTicks=4
   e:CancelAll('buyer');e:CancelAll('seller')
   local tick=math.round(entry)+side*10
   assert(quote(e,b,-1,1,tick));assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
   quote(e,b,1,100,tick-1);quote(e,b,-1,100,tick+1)
   local count=e.TotalVolume;local base=ac.Base;M.Step(p,a)
   assert(s.ExitReason=='Profit'and e.TotalVolume>count and ac.Base==base)
   local held=ac.Positions.BX;assert(not held or held.Direction==side);e:Audit()
  end
 end)
 test('A favorable last print cannot trigger profit without a profitable executable quote',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a)
  local ac=e.Accounts[a.Id];local pos=assert(ac.Positions.BX);local entry=math.round(pos.Entry/b.Spec.Tick)
  s.Phase='Holding';s.NextReview=e.Time+1000;s.ProfitAge=0;s.ProfitTicks=4
  e:CancelAll('buyer');e:CancelAll('seller')
  assert(quote(e,b,-1,1,entry+10));assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
  quote(e,b,1,100,entry-1);quote(e,b,-1,100,entry+11)
  local count=e.TotalVolume;M.Step(p,a);assert(s.Phase=='Holding'and e.TotalVolume==count);e:Audit()
 end)
 test('Profit age and targets diversify without shared draws; all horizons can signal',function()
  local e,p=fixture();local ages,targets={},{}
  for i=1,90 do local a=p:_agent('BT','Momentum',i);local before=p.Random.State;local s=M.Adopt(p,a)
   assert(p.Random.State==before and s.Confirmation<s.Horizon)
   assert(s.ProfitAge>=C.BotMomentum.ProfitMinAge and s.ProfitAge<=C.BotMomentum.ProfitMaxAge)
   ages[math.floor(s.ProfitAge/10)]=true;targets[math.floor(s.ProfitTicks/5)]=true
  end
  local na,nt=0,0;for _ in pairs(ages)do na+=1 end;for _ in pairs(targets)do nt+=1 end
  assert(na>=4 and nt>=4)
 end)
 test('Profit thresholds and pending execution continue identically after checkpoint restore',function()
  local e=E.new(copy(C),123);local p=P.new(e)
  for _=1,300 do p:Step()end
  local saved=CP.Capture(e,p);local re,rp=CP.Restore(CP.Decode(CP.Encode(saved)),C)
  equal(saved,CP.Capture(re,rp))
  for _=1,200 do p:Step();rp:Step()end
  equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
 end)
'''
src=(R/'original/server/BotMomentumTests.luau').read_text(encoding='utf8')
assert src.count(' return out\n')==1
for variant in ['profit','profit-patient']:
    (R/'variants'/variant/'BotMomentumTests.luau').write_text(src.replace(' return out\n',extra+' return out\n'),encoding='utf8')
