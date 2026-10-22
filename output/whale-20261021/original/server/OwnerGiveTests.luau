local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local W=require(script.Parent.WorldService)
local Command=require(script.Parent.OwnerGiveCommand)
local Liquidity=require(script.Parent.TestLiquidity)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local t={}for k,x in pairs(v)do t[k]=clone(x)end return t end
local function fresh()
 local e=E.new(C,934);local f=F.new(e,L,C);f:Join("101");return e,f,f:Owner("101")
end
local function world()
 local s={}
 function s:UpdateAsync(_,callback)
  if self.Fail then error("Injected grant write failure")end
  local v=callback(clone(self.Value));if v then self.Value=clone(v)end
  if self.LostReply then error("Injected lost grant confirmation")end
  return clone(v)
 end
 function s:GetAsync()return clone(self.Value)end
 local c=clone(C);c.WarmupSeconds=0
 local w=W.new(c,{Studio=false,PlaceId=123,JobId="give-test",CanOwn=true,Store=s,Now=function()return 1000 end})
 w:Open();assert(w:CanRun(),w.LastError)
 F.new(w.Engine,L,c):Join("101");assert(w:Save(false));return w,s
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
 test("Parser accepts exact usernames and positive whole dollars only",function()
  local name,n=Command.Parse(" /GIVE @Trader_123 50000 ");assert(name=="Trader_123"and n==50000)
  assert(select(2,Command.Parse("/give Trader 1000000000000"))==Command.MaxAmount)
  for _,v in ipairs({"/give","/give Trader","/give Trader 0","/give Trader -1","/give Trader 1.5","/give Trader nan","/give Trader inf","/give Trader 1e6","/give Trader 1000000000001","/give Display Name 100","/give Trader 100 extra","/give * 100"})do assert(not Command.Parse(v),v)end
 end)
 test("Amount shortcuts scale exact whole dollars and reject malformed or excessive amounts",function()
  for token,expected in pairs({["1k"]=1000,["1m"]=1000000,["10m"]=10000000,["1b"]=1000000000,["1t"]=1000000000000,
   ["1K"]=1000,["1.5M"]=1500000,["0.5B"]=500000000,["0.001T"]=1000000000,["1.001k"]=1001,["0.001k"]=1})do
   assert(select(2,Command.Parse("/give Trader "..token))==expected,token)
  end
  for _,token in ipairs({"1kk","1q","1..5m","1.m",".5m","-1m","0k","1.0001k","1.000000000001b","1.1t","2t","1e3k","1,000k"})do
   assert(not Command.Parse("/give Trader "..token),token)
  end
 end)
 test("Non-owner is rejected before any lookup or grant",function()
  local notices={};local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,
   Resolve=function()error("Unauthorized lookup")end,Give=function()error("Unauthorized grant")end,
   Notify=function(_,message)table.insert(notices,message)end})
  command:Handle({UserId=2},"/give Trader 50000");assert(#notices==1 and notices[1]:find("Only the experience owner"))
 end)
 test("Owner grant resolves canonical username and forwards only validated inputs",function()
  local count=0;local now=100;local player={UserId=1};local notices={}
  local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,Now=function()return now end,Ready=function()return true end,
   Resolve=function(name)assert(name=="trader");return 101,"Trader"end,
   Give=function(uid,name,amount,actor)assert(uid==101 and name=="Trader"and amount==50000 and actor==1);count+=1;return true,"Saved"end,
   Notify=function(_,message)table.insert(notices,message)end})
  command:Handle(player,"/give trader 50k");command:Handle(player,"/give trader 50k")
  assert(count==1 and notices[1]=="Saved"and not command.Busy)
  now+=3;command.Options.Resolve=function()return 101,"WrongUser"end
  command:Handle(player,"/give trader 50000");assert(count==1 and notices[#notices]:find("Username not found"))
 end)
 test("Group owner is authorized; group members and unavailable exchanges cannot grant",function()
  local count=0;local command=Command.new({CreatorType=Enum.CreatorType.Group,CreatorId=77,GroupLookup=function()return {Owner={Id=1}}end,
   Ready=function()return true end,Resolve=function()return 101,"Trader"end,Give=function()count+=1;return true,"Saved"end,Notify=function()end})
  command:Handle({UserId=2},"/give Trader 1");assert(count==0)
  command:Handle({UserId=1},"/give Trader 1");assert(count==1)
  command.Options.Ready=function()return false end;command:Handle({UserId=1},"/give Trader 1");assert(count==1)
 end)
 test("Grant adds capital without altering open trades, profit, ranks or statistics",function()
  local e,f,id=fresh();assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Market",StopTicks=10,TargetTicks=20}))
  local a=e.Accounts[id];local p=a.Positions.BX;local entry,stop,target=p.Entry,p.Stop,p.Target
  local tradeCount=e.NextTrade;assert(f:GrantMoney("101",50000,1,"receipt-a")==60000)
  assert(a.Base==60000 and a.Balance==60000 and a.Realized==0 and a.Limit==60 and a.Positions.BX==p)
  assert(p.Entry==entry and p.Stop==stop and p.Target==target and e.NextTrade==tradeCount)
  f:Evaluate("101");assert(f:Earned(f:Profile("101"))==0 and not next(f:Profile("101").Awards)and a.Stats.Trades==0)
  e:Audit()
 end)
 test("Receipt replay is idempotent after checkpoint restore",function()
  local e,f,id=fresh();f:GrantMoney("101",10000000000,1,"receipt-b")
  local pop=setmetatable({Engine=e,Config=C,Random=P.RNG.new(934),Agents={}},P)
  local r=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),C);local rf=F.new(r,L,C)
  assert(rf:GrantMoney("101",10000000000,1,"receipt-b")==10000010000)
  assert(r.Accounts[id].Balance==10000010000 and #rf:Profile("101").MoneyGrants==1)
  assert(not pcall(function()rf:GrantMoney("101",1,1,"receipt-b")end));r:Audit()
 end)
 test("Offline new players receive one account; malformed and blown-account grants fail",function()
  local e,f=fresh();assert(f:GrantMoney("202",50000,1,"offline")==60000)
  assert(#f:Profile("202").Ledger==1 and f:Owner("202"))
  local a=e.Accounts[f:Owner("101")];a.Depleted=true;a.Locked=true
  assert(not pcall(function()f:GrantMoney("101",1,1,"failed")end));assert(a.Balance==10000)
  for _,value in ipairs({0,-1,1.5,math.huge,0/0,1000000000001})do
   assert(not pcall(function()f:GrantMoney("202",value,1,"invalid")end))
  end
  assert(e.Accounts[f:Owner("202")].Balance==60000);e:Audit()
 end)
 test("Confirmed save installs the grant and survives reload",function()
  local w,s=world();local original=w.Engine
  local ok,balance=w:TransformSaved(function(e)return F.new(e,L,C):GrantMoney("101",1000000000000,1,"saved")end)
  assert(ok and balance==1000000010000 and w.Engine~=original)
  local r=CP.Restore(CP.Decode(s.Value.Checkpoint),C);assert(r.Accounts[r.Profiles["101"].Account].Balance==1000000010000);r:Audit()
 end)
 test("Trillion-dollar grants retain trading and account limit safeguards",function()
  local e,f,id=fresh();f:GrantMoney("101",1000000000000,1,"trillion")
  assert(Liquidity.Submit(e,id,{Contract="BG",Direction=1,Quantity=3,Type="Market"}))
  assert(Liquidity.Perform(e,id,{Action="Close",Contract="BG"}));e:Audit()
  assert(f:Earned(f:Profile("101"))==e.Accounts[id].Realized)
  f:GrantMoney("101",1000000000000,1,"second");f:GrantMoney("101",1000000000000,1,"third")
  local before=e.Accounts[id].Balance
  assert(not pcall(function()f:GrantMoney("101",1000000000000,1,"over-limit")end))
  assert(e.Accounts[id].Balance==before);e:Audit()
 end)
 test("Failed save never credits the live or durable account",function()
  local w,s=world();s.Fail=true
  assert(not w:TransformSaved(function(e)return F.new(e,L,C):GrantMoney("101",50000,1,"fail")end))
  assert(not w.Engine and not w:CanRun());s.Fail=false;w:Open();assert(w:CanRun())
  assert(w.Engine.Accounts[w.Engine.Profiles["101"].Account].Balance==10000)
 end)
 test("Lost acknowledgement recovers exactly the committed grant",function()
  local w,s=world();s.LostReply=true
  assert(not w:TransformSaved(function(e)return F.new(e,L,C):GrantMoney("101",50000,1,"lost")end))
  s.LostReply=false;w:Open();assert(w:CanRun())
  local f=F.new(w.Engine,L,C);assert(f:GrantMoney("101",50000,1,"lost")==60000)
  assert(w.Engine.Accounts[f:Owner("101")].Balance==60000);w.Engine:Audit()
 end)
 return rows
end
return Tests
