local Stats=require(script.Parent.BotStats)
local Command=require(script.Parent.OwnerBotsCommand)
local Refresh=require(script.Parent.BotRefresh)
local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Tests={}
local function copy(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function equal(a,b)
 assert(type(a)==type(b));if type(a)~="table"then assert(a==b);return end
 for k,v in pairs(a)do equal(v,b[k])end for k in pairs(b)do assert(a[k]~=nil)end
end
local function near(a,b)assert(math.abs(a-b)<.001,tostring(a).." ~= "..tostring(b))end
local function fixture()
 local c=copy(C);c.PlayerExecution=nil;c.Contracts.BX.Last=5000
 local e=E.new(c,771);local p={Agents={}}
 local a=e:AddAccount("bot:long",100000,100,.8,false)
 table.insert(p.Agents,{Id=a.Id,Kind="Maker",Key="BX"})
 e:AddAccount("private-player",1000000,100,.8,true)
 assert(e:Submit("private-player",{Contract="BX",Direction=-1,Quantity=2,Type="Limit",Price=5000}))
 assert(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=2,Type="Market"}))
 e.Books.BX.Last=5010/.25
 local b=e:AddAccount("bot:retired",30000,20,.8,false)
 table.insert(p.Agents,{Id=b.Id,Kind="Value",Key="BX",Retiring=true})
 local house=e:AddAccount("private-clearing",1000000000,100,.8,false);house.House=true
 local archive=e:AddAccount("private-archive",999,1,.8,false);archive.Archive=true
 -- Even malformed population membership cannot expose these accounts.
 for _,id in ipairs({"private-player","private-clearing","private-archive"})do table.insert(p.Agents,{Id=id})end
 return e,p,a
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("Stats reconcile type/market totals, include retiring bots and exclude private accounts",function()
  local e,p=fixture();local r=Stats.Capture(e,p)
  assert(r.Total.Count==2 and r.Total.Active==1 and r.Total.Retired==1)
  near(r.Total.Allocation,1000000);near(r.Total.Balance,130000);near(r.Total.Equity,131000)
  near(r.Total.Realized,0);near(r.Total.Unrealized,1000);near(r.Total.Pnl,1000)
  assert(r.Total.Positions==1 and r.Total.Contracts==2)
  near(r.Kinds.Maker.Pnl+r.Kinds.Value.Pnl,r.Markets.BX.Pnl)
  local text=Stats.Format(r)
  assert(text:find("BY BOT TYPE",1,true)and text:find("BY MARKET",1,true)and text:find("INDIVIDUAL BOTS",1,true))
  assert(not text:find("private",1,true)and #text<Stats.MaxBytes)
 end)
 test("Inspection and formatting are deterministic and do not mutate the exchange",function()
  local e,p=fixture();local accounts,books,orders,agents=copy(e.Accounts),copy(e.Books),copy(e.Orders),copy(p)
  local first=Stats.Text(e,p);assert(first==Stats.Text(e,p))
  equal(accounts,e.Accounts);equal(books,e.Books);equal(orders,e.Orders);equal(agents,p)
  -- A detached report may be edited without changing an account.
  local r=Stats.Capture(e,p);r.Bots[1].Equity=7;equal(accounts,e.Accounts)
 end)
 test("Reports use refresh P&L baselines instead of counting historical profit or funding",function()
  local e,p,a=fixture();local plan=Refresh.Prepare(e,p,1,1);Refresh.Apply(e,p,plan);e:Audit()
  -- Retiring accounts are reported but do not receive refresh funding.
  local r=Stats.Capture(e,p);near(r.Total.Pnl,0);near(r.Total.Equity,780000);assert(r.Refresh.Sequence==1)
  near(e.Accounts['bot:retired'].Balance,30000);near(r.Total.CapitalAdjusted,649000)
  e.Books.BX.Last=5012/.25;r=Stats.Capture(e,p);near(r.Total.Pnl,200);near(r.Total.Unrealized,200)
  assert(Stats.Format(r):find("Last bot refresh: #1",1,true));near(a.Realized,0)
 end)
 test("Depleted equity, pending exits, working and queued orders are counted accurately",function()
  local e,p,a=fixture();a.Positions.BX.Triggered="Stop loss";e.Books.BX.Last=3900/.25
  assert(e:Submit("bot:retired",{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=3800}))
  local r=Stats.Capture(e,p);assert(r.Total.Depleted==1 and r.Total.Exits==1 and r.Total.Orders==1)
  local id=next(e.Accounts["bot:retired"].OpenOrders);e.Orders[id].Queued=true
  r=Stats.Capture(e,p);assert(r.Total.Queued==1)
 end)
 test("Empty populations format without division by zero",function()
  local e=E.new(copy(C),1);local r=Stats.Capture(e,{Agents={}})
  assert(r.Total.Count==0 and not Stats.Format(r):find("nan",1,true))
 end)
 test("Exit diagnostics distinguish order age from fill age and stale references without mutation",function()
  local e,p,a=fixture();local pos=a.Positions.BX;pos.Triggered='Take profit';pos.Target=5020
  e.Time=100;local ok,r=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=2,Type='Limit',Price=5020,ReduceOnly=true})
  assert(ok and r.Remaining==2);pos.ExitOrder=r.Id;e.Time=130;a.LastBotFillAt=10
  local row=Stats.Capture(e,p).Bots[1];assert(row.LastFill=='120'and row.ExitOrderAge=='30'and row.ExitState:find('Resting limit',1,true))
  p.Agents[1].RecoveryReadyAt=200;row=Stats.Capture(e,p).Bots[1]
  assert(row.ExitState:find('Recovery awaiting',1,true))
  p.Agents[1].RecoveryReadyAt=nil;e:Cancel(a.Id,r.Id);row=Stats.Capture(e,p).Bots[1]
  assert(row.ExitOrderAge=='unknown'and row.ExitState:find('No working exit order',1,true))
 end)
 test("Exact stats parsing and server ownership prevent unauthorized report generation",function()
  assert(Command.Parse(" /BOTS STATS ")=="stats"and Command.Parse("/bots refresh")=="refresh")
  for _,s in ipairs({"/bots stats all","/bots status","/botsstats","/bots","/bots stats\nrefresh"})do assert(not Command.Parse(s))end
  local calls=0;local messages={};local actor={UserId=1}
  local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,StatsReady=function()return true end,
   Stats=function(player)assert(player==actor);calls+=1 end,Notify=function(_,m)table.insert(messages,m)end,
   Ready=function()error("Stats cannot enter refresh flow")end,NextSequence=function()error("Stats cannot allocate a reset receipt")end})
  command:Handle({UserId=2},"/bots stats");assert(calls==0 and messages[1]:find("Only the experience owner",1,true))
  command:Handle(actor,"/bots stats");command:Handle(actor,"/bots stats");assert(calls==1 and not command.Pending and not command.Busy)
 end)
 test("Group-owner reports are private and unavailable worlds fail closed",function()
  local count=0;local command=Command.new({CreatorType=Enum.CreatorType.Group,CreatorId=77,
   GroupLookup=function()return {Owner={Id=1}}end,StatsReady=function()return true end,
   Stats=function()count+=1 end,Notify=function()end})
  command:Handle({UserId=2},"/bots stats");command:Handle({UserId=1},"/bots stats");assert(count==1)
  command.Options.StatsReady=function()return false end;command:Handle({UserId=1},"/bots stats");assert(count==1)
  command.Options.GroupLookup=function()error("lookup failed")end;command:Handle({UserId=1},"/bots stats");assert(count==1)
 end)
 test("Stats failures do not block a later refresh or leak internal error details",function()
  local message;local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,StatsReady=function()return true end,
   Stats=function()error("private error")end,Notify=function(_,m)message=m end,Ready=function()return true end,NextSequence=function()return 1 end})
  command:Handle({UserId=1},"/bots stats");assert(message:find("could not be prepared",1,true)and not message:find("private error",1,true))
  command:Handle({UserId=1},"/bots refresh");assert(command.Pending and command.Pending.Sequence==1)
 end)
 return rows
end
return Tests
