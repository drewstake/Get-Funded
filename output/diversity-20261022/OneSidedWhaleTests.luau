local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local W=require(script.Parent.BotWhale)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function fixture(side,passive)
 local c=copy(C);c.BotWhale.AggressiveProbability=passive and {0,0}or {1,1};c.BotWhale.SliceSeconds={1,1};c.BotWhale.RefillSeconds={3,3}
 local e=E.new(c,123);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(123),Agents={},Markets={BX={},BT={},BG={}}},P)
 local a=p:_agent('BX','Whale',1);a.Size=40;a.Limit=40;e.Accounts[a.Id].Limit=40
 local b=e.Books.BX;e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
 local s=W.Adopt(p,a);s.CooldownUntil=0;s.BuildSeconds=100;s.HoldSeconds=50;s.ReduceSeconds=40;s.TargetFraction=.5;s.Participation=.1;s.PriceTolerance=10
 W.Step(p,a);s.Side=side or 1;s.Target=s.Quantity*s.Side;s.StartSideFills=0
 return e,p,a,b,s
end
local function quote(e,b,side,qty,tick)
 local ok,r=e:Submit(side==1 and 'buyer'or 'seller',{Contract=b.Key,Direction=side,Quantity=qty or 100,Type='Limit',Price=(tick or (b.Last or b.Reference)-side)*b.Spec.Tick})
 assert(ok,tostring(r));return r
end
local function advance(e,p,a,seconds)e:AdvanceClock(seconds or 5);W.Step(p,a)end
local function enter(side,passive)
 local e,p,a,b,s=fixture(side,passive);quote(e,b,1);quote(e,b,-1);advance(e,p,a,10);return e,p,a,b,s
end
function T.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 for _,side in ipairs({1,-1})do for _,passive in ipairs({false,true})do
  test('Missing required quote never falls through to the other side: '..tostring(side)..'/'..tostring(passive),function()
   local e,p,a,b,s=fixture(side,passive)
   quote(e,b,passive and -side or side)
   local orders=e.NextOrder;local volume=e.TotalVolume;local last=b.Last
   advance(e,p,a,10)
   assert(e.NextOrder==orders and e.TotalVolume==volume and b.Last==last and not s.ChildId and not next(e.Accounts[a.Id].OpenOrders))
   e:Audit()
  end)
 end end

 return out
end
return T
