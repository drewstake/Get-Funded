 test("Repricing withdraws first and waits for an individual replacement clock",function()
  local e,p,a=fixture(1);local b=e.Books.BX;local slot='-1:1';local id=a.Quotes[slot]
  local old=e.Orders[id];local cash=e.Accounts[a.Id].Balance;local volume=e.TotalVolume;local last=b.Last
  -- A wider quoted spread tests repricing without fabricating a trade or editing the book.
  p.Regime.Volatility=8;e.Time=C.MakerMinRestSeconds+1
  p:_maker(a)
  assert(not e.Orders[id]and not a.Quotes[slot]);local due=a.ReplenishAt[slot];assert(due>e.Time)
  p:_maker(a);assert(not a.Quotes[slot]);assert(e.TotalVolume==volume and b.Last==last and e.Accounts[a.Id].Balance==cash)
  e.Time=due;p:_maker(a);assert(a.Quotes[slot]and a.Quotes[slot]~=id);e:Audit()
 end)
 test("Maker refill profiles are diverse, repeatable and do not draw shared randomness",function()
  local e,p,a=fixture(1);local factors={};local n=0
  for i=2,20 do local agent=p:_agent('BX','Maker',i);local before=p.Random.State;p:_maker(agent);assert(before==p.Random.State)
   assert(agent.QuoteRefillFactor>=.6 and agent.QuoteRefillFactor<=1.4)
   local bucket=math.floor(agent.QuoteRefillFactor*10);if not factors[bucket]then factors[bucket]=true;n+=1 end
   local value=agent.QuoteRefillFactor;agent.QuoteRefillFactor=nil;p:_maker(agent);assert(agent.QuoteRefillFactor==value)
  end
  assert(n>=4);e:Audit()
 end)
 test("Maker adoption preserves manual exits, stop removal, balances and live inventory",function()
  local e,p,a=fixture(1);local b=e.Books.BX;local ac=e.Accounts[a.Id]
  assert(e:Submit('taker',{Contract='BX',Direction=-1,Quantity=2,Type='Market'}))
  local pos=ac.Positions.BX;assert(pos and pos.Direction==1);pos.Stop=nil;pos.ManualStop=true
  local ok,result=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=(b.Last+50)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  local before=clone(pos);local cash=ac.Balance;local volume=e.TotalVolume;a.QuotePolicy=7;p:_maker(a)
  equal(before,pos);assert(e.Orders[result.Id]and ac.Balance==cash and e.TotalVolume==volume);e:Audit()
 end)
 test("V27 policy migration is economically read-only and refuses policy downgrade",function()
  local e=E.new(clone(C),71);local p=P.new(e);local saved=Checkpoint.Capture(e,p)
  saved.Version=27;saved.Config.MakerQuotePolicyVersion=7;saved.Config.MakerRepricePause=nil;saved.Config.BotMomentum.Version=1
  local before=clone(saved);local re,rp=Checkpoint.Restore(saved,C)
  equal(saved,before);equal(saved.Engine,Checkpoint.Capture(re,rp).Engine)
  assert(re.Config.MakerQuotePolicyVersion==8 and re.Config.BotMomentum.Version==2)
  local old=clone(C);old.MakerQuotePolicyVersion=7;assert(not pcall(Checkpoint.Restore,Checkpoint.Capture(re,rp),old));re:Audit()
 end)
 test("Pending staggered Maker replacements survive a complete checkpoint replay",function()
  local e=E.new(clone(C),7919);local p=P.new(e)
  for _,a in ipairs(p.Agents)do if a.Kind=='Maker'then
   local id=a.Quotes['1:1'];if id then e:Cancel(a.Id,id);p:_maker(a)end
  end end
  local saved=Checkpoint.Decode(Checkpoint.Encode(Checkpoint.Capture(e,p)));local re,rp=Checkpoint.Restore(saved,C)
  for i=1,100 do p:Step();rp:Step()end
  equal(Checkpoint.Capture(e,p),Checkpoint.Capture(re,rp));e:Audit();re:Audit()
 end)
