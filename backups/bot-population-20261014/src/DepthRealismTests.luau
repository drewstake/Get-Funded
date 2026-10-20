local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local Policy=require(script.Parent.PlayerExecution)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local t={}for k,x in pairs(v)do t[k]=clone(x)end return t end
local function fixture(config,seed)local e=E.new(config or clone(C),seed or 4141);return e,P.new(e)end
local function fixed()
 local c=clone(C);c.ParticipantsPerInstrument=0;c.MakersPerInstrument=0;c.ScalpersPerInstrument=0;c.WhaleFrequency=0;c.NewsFrequency=0
 c.Regimes={{Name="Fixed",Weight=1,Volatility=0,Liquidity=1,Activity=1,Trend=0}}
 return c
end
local function counts(book)
 local result={};for _,side in ipairs({"Bids","Asks"})do result[side]={};for _,l in ipairs(book[side])do table.insert(result[side],l.Quantity)end end
 return result
end
function Tests.Run()
 local results={};local function test(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test("Production reserve quotes vary by instrument and occupy consecutive ticks",function()
  local e,p=fixture(fixed());local report={}
  for _,key in ipairs(C.ContractOrder)do
   local b=e.Books[key];report[key]=counts(b)
   for _,side in ipairs({"Bids","Asks"})do
    assert(#b[side]==5)
    for i,l in ipairs(b[side])do
     assert(l.Quantity>0 and l.Quantity<500,"Oversized reserve wall")
     if i>1 then assert(math.abs(l.Price-b[side][i-1].Price)==1,"Reserve ladder skipped ticks")end
     local sum=0;for _,o in ipairs(l.Orders)do assert(o.Remaining<100);sum+=o.Remaining end
     assert(sum==l.Quantity,"Displayed depth differs from executable orders")
    end
   end
  end
  assert(e.Books.BX.Asks[1].Quantity>e.Books.BT.Asks[1].Quantity*3)
  e:Audit();return report
 end)
 test("Cancelling and resubmitting cannot drain smaller production books",function()
  local e,p=fixture(fixed());e:AddAccount("spam",2000000,2000,.8,true)
  local report={}
  for _,key in ipairs(C.ContractOrder)do
   local before=Policy.Liquidity(e,e.Books[key],1);local filled=0
   for _=1,100 do
    local ok,r=e:Submit("spam",{Contract=key,Direction=1,Quantity=1000,Type="Market"});assert(ok)
    filled+=r.Filled;if e.Orders[r.Id]then e:Cancel("spam",r.Id)end
   end
   assert(filled>0 and filled<=math.floor(before*C.PlayerExecution.BookFraction))
   assert(#e.Books[key].Asks>0 and #e.Books[key].Bids>0)
   report[key]={InitialContracts=before,FilledAcross100Clicks=filled,RemainingContracts=Policy.Liquidity(e,e.Books[key],1)}
  end
  e:Audit();return report
 end)
 test("Thirty-two waiting players share the smaller production allowance",function()
  local e,p=fixture(fixed());local ids={}
  for i=1,32 do
   local id="waiting-"..i;table.insert(ids,id);e:AddAccount(id,10000000000,10000000,.8,true)
   assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=1000000,Type="Market",Execution="Sliced"}))
  end
  for _=1,2 do
   e:AdvanceClock(C.PlayerExecution.WindowSeconds)
   for _,a in ipairs(p.Agents)do p:_reserve(a)end
   for _=1,8 do e:ProcessPlayerOrders()end
  end
  for _,id in ipairs(ids)do assert(e.Accounts[id].Positions.BX,"Player starved in the smaller book")end
  assert(#e.Books.BX.Asks>0 and #e.Books.BX.Bids>0);e:Audit()
  return "All 32 players receive fills without exhausting displayed depth"
 end)
 test("Small quotes replenish through new finite orders after consumption",function()
  local e,p=fixture(fixed());local a=p.Agents[1];local old=a.Quotes["-1:1"];local order=e.Orders[old]
  local consumer=e:AddAccount("consumer",1000000000,100000,.8,false)
  local quantity=e.Books[a.Key].Asks[1].Quantity
  local ok,r=e:Submit(consumer.Id,{Contract=a.Key,Direction=1,Quantity=quantity,Type="Market"})
  assert(ok and r.Filled==quantity and not e.Orders[old])
  p:_reserve(a);local replacement=e.Orders[a.Quotes["-1:1"]]
  assert(replacement and replacement.Id~=old and replacement.Remaining<100)
  e:Audit();return "Consumed quotes are replaced with small real orders; large capital stays off the displayed book"
 end)
 test("Old enormous quotes are withdrawn on restore without resetting positions or balances",function()
  local legacy=fixed();legacy.ReservePopulationVersion=1;legacy.Reserve.QuoteSize=100000;legacy.Reserve.QuoteSizes=nil
  legacy.Reserve.SizeVariation=nil;legacy.Reserve.DepthGrowth=.5;legacy.Reserve.Offsets={2,4,8,12,16}
  local e,p=fixture(legacy);local a=e:AddAccount("saved-player",2000000,2000,.8,true)
  assert(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1000,Type="Market"}))
  local pendingOk,pending=e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=(e.Books.BX.Reference-10)*e.Books.BX.Spec.Tick});assert(pendingOk)
  local saved=Checkpoint.Capture(e,p);local restored,rp=Checkpoint.Restore(saved,C)
  assert(restored.NextTrade==e.NextTrade and restored.TotalVolume==e.TotalVolume and restored.TradeHash==e.TradeHash)
  assert(restored.Accounts[a.Id].Balance==a.Balance and restored.Accounts[a.Id].Positions.BX.Quantity==a.Positions.BX.Quantity)
  assert(restored.Orders[pending.Id]and restored.Orders[pending.Id].Remaining==1)
  for _,agent in ipairs(rp.Agents)do if agent.Kind=="Reserve"then
   assert(agent.Size==C.Reserve.QuoteSizes[agent.Key]and not next(restored.Accounts[agent.Id].OpenOrders))
   assert(restored.Accounts[agent.Id].Balance==e.Accounts[agent.Id].Balance)
   rp:_reserve(agent)
  end end
  for _,o in pairs(restored.Orders)do if o.Owner~=a.Id then assert(o.Remaining<100)end end
  local nextSave=Checkpoint.Capture(restored,rp);local again,ap=Checkpoint.Restore(nextSave,C)
  assert(again.NextOrder==restored.NextOrder and #ap.Agents==#rp.Agents)
  again:Audit();return "Balances, existing positions, player orders and trade history preserved; obsolete bot walls removed once"
 end)
 test("Actual production simulation remains finite, varied and deterministic",function()
  local report={}
  for _,seed in ipairs({4141,73521,90871})do
   local e,p=fixture(nil,seed);local stats={}
   for _,key in ipairs(C.ContractOrder)do stats[key]={Samples=0,Total=0,Max=0,Empty=0}end
   for step=1,800 do
    p:Step()
    if step%20==0 then for _,key in ipairs(C.ContractOrder)do
     local s=stats[key];local b=e.Books[key]
     if #b.Bids==0 or #b.Asks==0 then s.Empty+=1 end
     for _,side in ipairs({b.Bids,b.Asks})do for i=1,math.min(5,#side)do
      s.Samples+=1;s.Total+=side[i].Quantity;s.Max=math.max(s.Max,side[i].Quantity)
      assert(side[i].Quantity<5000,"Artificial oversized level returned")
     end end
    end end
   end
   for _,s in pairs(stats)do s.Mean=math.floor(s.Total/math.max(1,s.Samples)*10)/10 end
   local restored,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(Checkpoint.Capture(e,p))),C)
   for _=1,40 do p:Step();rp:Step()end
   assert(e.TradeHash==restored.TradeHash and e.NextTrade==restored.NextTrade)
   e:Audit();restored:Audit();table.insert(report,{Seed=seed,Depth=stats})
  end
  return report
 end)
 return results
end
return Tests
