-- Market removal must preserve BX, saved equity and all archived evidence.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Fixtures=require(script.Parent.TestMarkets)
local V2=Fixtures.BXVersion2()
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local R=require(script.Parent.LegacyRetirement)
local Refresh=require(script.Parent.BotRefresh)
local T=require(script.Parent.TestLiquidity)
local Tests={}
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function fixture()
 local c=Fixtures.ThreeMarkets();c.MarketRetirementVersion=1
 c.Contracts.RTY=copy(c.LegacyContracts.RTY);table.insert(c.ContractOrder,'RTY')
 local e=E.new(c,793);local p=P.new(e);R.Apply(e,p)
 for _=1,40 do p:Step()end
 local player=e:AddAccount('preserved-player',260000,260,.8,true)
 T.FillAt(e,player.Id,{Contract='BX',Type='Market',Direction=1,Quantity=1})
 local saved=CP.Capture(e,p);saved.Version=31;return e,p,player,saved
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and(r or 'Passed')or tostring(r)})end
 test('Fresh production exchanges run only 1170 BX participants and reject retired markets',function()
  assert(#C.ContractOrder==1 and C.ContractOrder[1]=='BX'and not C.Contracts.BT and not C.Contracts.BG)
  local e=E.new(copy(C),791);local p=P.new(e);assert(#p.Agents==1170)
  for _,a in ipairs(p.Agents)do assert(a.Key=='BX')end
  local player=e:AddAccount('player',1000000,1000,.8,true)
  for _,key in ipairs({'BT','BG'})do
   assert(C.LegacyContracts[key].CloseOnly and not e.Books[key])
   assert(not e:Submit(player.Id,{Contract=key,Type='Market',Direction=1,Quantity=1}))
  end
  assert(e:OrderCapacity(player,'BX',1)<=200);e:Audit()
 end)
 test('V31 retirement preserves BX accounts, orders, chart, safety history and existing archives',function()
  local e,p,player,saved=fixture();local unchanged=copy(saved)
  local r,rp=CP.Restore(saved,V2);equal(unchanged,saved)
  assert(#rp.Agents==390 and #r.Config.ContractOrder==1 and not r.Books.BT and not r.Books.BG)
  equal(e.Accounts[player.Id],r.Accounts[player.Id],'player')
  equal(e.Books.BX,r.Books.BX,'BX book');equal(p.Markets.BX,rp.Markets.BX,'BX signals')
  equal(e.MarketRetirement.Markets.RTY,r.MarketRetirement.Markets.RTY,'previous archive')
  local agents={};for _,a in ipairs(p.Agents)do agents[a.Id]=a end
  local priorAccounts={};for _,a in ipairs(saved.Engine.Accounts)do priorAccounts[a.Id]=a end
  for _,a in ipairs(rp.Agents)do equal(agents[a.Id],a,'BX agent');equal(e.Accounts[a.Id].OpenOrders,r.Accounts[a.Id].OpenOrders,'BX working orders')end
  for _,a in ipairs(CP.Capture(r,rp).Engine.Accounts)do equal(priorAccounts[a.Id],a,'saved account '..a.Id)end
  assert(#r.MarketRetirement.Accounts==780 and r.MarketRetirement.Version==2)
  for _,a in ipairs(r.MarketRetirement.Accounts)do
   assert(not r.Accounts[a.Id]and not next(a.Positions)and not next(a.OpenOrders))
   local prior=e.Accounts[a.Id];assert(math.abs(a.Balance-e:Summary(prior).Equity)<.001)
   assert(a.Base==prior.Base and a.NetCapitalAdjustments==prior.NetCapitalAdjustments)
  end
  for _,key in ipairs({'BT','BG'})do
   equal(e.Books[key].Candles,r.MarketRetirement.Markets[key].Book.Candles,key..' candles')
  end
  for _,field in ipairs({'NextTrade','TotalVolume','TradeHash','Step','Time','Execution','RequestJournal'})do equal(e[field],r[field],field)end
  assert(p.Random.State==rp.Random.State);r:Audit()
 end)
 test('Outstanding retired-market player exposure settles at saved equity without trades or rewards',function()
  local e,p,player=fixture()
  T.FillAt(e,player.Id,{Contract='BT',Type='Market',Direction=-1,Quantity=1})
  T.FillAt(e,player.Id,{Contract='BG',Type='Market',Direction=1,Quantity=1})
  local before=copy(player);local equity=e:Summary(player).Equity;local bx=copy(player.Positions.BX)
  local saved=CP.Capture(e,p);saved.Version=31;local r,rp=CP.Restore(saved,V2);local after=r.Accounts[player.Id]
  assert(not after.Positions.BT and not after.Positions.BG);equal(bx,after.Positions.BX)
  assert(math.abs(r:Summary(after).Equity-equity)<.001)
  equal(before.History,after.History);equal(before.Fills,after.Fills)
  assert(after.Stats.Trades==before.Stats.Trades and r.NextTrade==e.NextTrade)
  local settlements=0;for _,row in ipairs(r.MarketRetirement.Settlements)do if row.Owner==player.Id then
   settlements+=1;assert(row.Price==(e.Books[row.Contract].Last or e.Books[row.Contract].Reference)*e.Books[row.Contract].Spec.Tick)
  end end;assert(settlements==2);r:Audit()
 end)
 test('Restart cannot resurrect retired markets, duplicate settlement, or fund extra BX bots',function()
  local _,_,_,saved=fixture();local e,p=CP.Restore(saved,V2);local before=CP.Capture(e,p)
  R.Apply(e,p);equal(before,CP.Capture(e,p))
  local r,rp=CP.Restore(CP.Decode(CP.Encode(before)),V2);equal(before,CP.Capture(r,rp))
  local old=Fixtures.ThreeMarkets();old.MarketRetirementVersion=1
  assert(not pcall(CP.Restore,before,old),'Old configuration reopened retired markets')
  local plan=Refresh.Prepare(e,p,1,1);assert(plan.Receipt.Count==390)
  local frozen=copy(e.MarketRetirement)
  for _=1,80 do p:Step();rp:Step()end
  equal(CP.Capture(e,p),CP.Capture(r,rp));equal(frozen,e.MarketRetirement)
  for _,o in pairs(e.Orders)do assert(o.Contract=='BX')end;e:Audit();r:Audit()
 end)
 return rows
end
return Tests
