-- Disposable Studio validation. Every order below belongs to a separate test engine.
local H=game:GetService("HttpService")
local shared=game.ReplicatedStorage.MarketReign
local server=game.ServerScriptService.MarketReign
local report={Checks={},Suites={}}
local ok,err=xpcall(function()
 local Access=require(server.MarketDepthAccess)
 local player={UserId=123};local clock=0;local owns=false;local broken=false;local calls=0
 local api={UserOwnsGamePassAsync=function(_,uid,id)calls+=1;assert(uid==123 and id==12345);if broken then error("Test service failure")end;return owns end}
 local access=Access.new(0,api,function()return clock end)
 local function packet()return {Quotes={BX={Depth={Bids={{Price=1,Quantity=2}},Asks={}}},BT={Depth={Bids={},Asks={}}}}}end
 local function check(name,value)assert(value,name);table.insert(report.Checks,name)end
 access:Refresh(player);local p=packet();access:Apply(p,player,"BX")
 check("Unconfigured pass locks all symbols without ownership queries",calls==0 and not p.DepthAccess.Allowed and not p.Quotes.BX.Depth and not p.Quotes.BT.Depth)
 access=Access.new(12345,api,function()return clock end)
 p=packet();access:Apply(p,player,"BX");check("Pending ownership fails closed",not p.DepthAccess.Allowed and not p.Quotes.BX.Depth)
 access:Refresh(player);task.wait();p=packet();access:Apply(p,player,"BX")
 check("Verified non-owner receives no depth",calls==1 and p.DepthAccess.State=="Locked"and not p.Quotes.BX.Depth)
 owns=true;access:Refresh(player,true);task.wait();p=packet();local depth=p.Quotes.BX.Depth;access:Apply(p,player,"BX")
 check("Verified owner receives only selected symbol's exact depth",p.DepthAccess.Allowed and p.Quotes.BX.Depth==depth and not p.Quotes.BT.Depth)
 broken=true;access:Refresh(player,true);task.wait();p=packet();access:Apply(p,player,"BX")
 check("Ownership errors revoke depth and report unavailable",not p.DepthAccess.Allowed and p.DepthAccess.State=="Unavailable"and not p.Quotes.BX.Depth)
 access:Forget(player);check("Leaving removes verified state",not access:Status(player).Allowed)
 local Config=require(shared.MarketConfig);local Engine=require(server.MarketEngine)
 local e=Engine.new(Config,92117)
 for _,id in ipairs({"A","B","C"})do e:AddAccount(id,1000000,500,.9,false)end
 assert(e:Submit("A",{Contract="BX",Type="Limit",Direction=-1,Quantity=3,Price=6000}))
 assert(e:Submit("B",{Contract="BX",Type="Limit",Direction=-1,Quantity=7,Price=6000}))
 local snapshot=e:Snapshot("C","BX","1m",true)
 check("Actual resting orders aggregate at a single price",#snapshot.Quotes.BX.Depth.Asks==1 and snapshot.Quotes.BX.Depth.Asks[1].Quantity==10 and snapshot.Quotes.BX.Depth.Asks[1].Price==6000)
 check("An empty engine side stays empty",#snapshot.Quotes.BX.Depth.Bids==0)
 for _,name in ipairs({"SharedDepthTests","MarketTests","TradeLimitsTests","TradeAmendmentTests","TradePreferencesTests","WorldTests","SingleAccountTests","OwnerResetTests"})do
  local tests=require(server[name]);local result=type(tests)=="function"and tests()or tests.Run()
  report.Suites[name]=result
  if result.Cases then assert(result.Passed,name)else for _,row in ipairs(result.Results or result)do assert(row.Passed,name..": "..row.Name..": "..tostring(row.Detail))end end
 end
 local engine=Engine.new(Config,73521);local population=require(server.Participants).new(engine)
 for _=1,math.floor(Config.WarmupSeconds/Config.StepSeconds)do population:Step()end
 local funded=require(server.FundedAccounts).new(engine,require(shared.ProgressionConfig),Config)
 funded:Start("l2fixture");funded:Flag("l2fixture","TutorialDone")
 local owner=funded:Owner("l2fixture");local first=engine:Snapshot(owner,"BX","1m",true)
 first.CandlesBySeries={}
 for _,key in ipairs(Config.ContractOrder)do for _,tf in ipairs(Config.Timeframes)do first.CandlesBySeries[key..":"..tf[1]]=engine:Snapshot(owner,key,tf[1],true).Candles end end
 first.Portfolio=funded:View("l2fixture")
 for _=1,10 do population:Step()end
 local second=engine:Snapshot(owner,"BX","1m",true)
 local value=Instance.new("StringValue");value.Name="Level2FixtureSnapshot";value.Value=H:JSONEncode({First=first,Second=second});value.Parent=shared
end,debug.traceback)
report.Ok=ok;report.Error=not ok and tostring(err)or nil
local result=Instance.new("StringValue");result.Name="Level2ServerResult";result.Value=H:JSONEncode(report);result.Parent=shared
print("LEVEL2_SERVER "..result.Value)
