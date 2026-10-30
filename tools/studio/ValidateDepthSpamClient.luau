-- Template: insert current MarketClient at the marker; run against the disposable shared graph.
local now=100
local Market=(function()
 local script=game.ReplicatedStorage.DepthSpamShared.MarketClient
 local os={clock=function()return now end}
 -- INSERT_CLIENT_SOURCE
end)()
local session=Market.New(nil,true);session.Preview=false;session.CanTrade=true;session.Ready=true
local sent={};session.Remote={FireServer=function(_,request)table.insert(sent,request)end}
local results={}
local function check(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
check("1000 clicks send only six requests and return clear feedback",function()
 local accepted,rejected=0,0
 for _=1,1000 do local ok,message=session:Place("BX",1,1,"Market")
  if ok then accepted+=1 else rejected+=1;assert(message:find("too quickly"))end
 end
 assert(accepted==6 and rejected==994 and #sent==6)
 return {Clicks=1000,Sent=accepted,LocallyRejected=rejected}
end)
check("Allowance refills; throttled clicks are never replayed",function()
 now+=.21;assert(session:Place("BX",1,1,"Market"));assert(#sent==7)
 assert(not session:Place("BX",1,1,"Market"));now+=2
 assert(session:Place("BX",1,1,"Market"));assert(#sent==8)
end)
check("Close and cancel remain available after exhausting the entry burst",function()
 for _=1,20 do session:Place("BX",1,1,"Market")end
 assert(session:Close("BX"));assert(session:Cancel(1))
 assert(sent[#sent-1].Action=="Close"and sent[#sent].Action=="Cancel")
end)
check("Missing replies cannot grow the pending tracker beyond 64 entries",function()
 for _=1,250 do session:Cancel(1)end
 local n=0;for _ in pairs(session.Pending)do n+=1 end;assert(n==64)
 now+=31;session:Cancel(1);n=0;for _ in pairs(session.Pending)do n+=1 end;assert(n==1)
end)
check("Read requests do not accumulate pending acknowledgements",function()
 local before=table.clone(session.Pending)
 for _=1,10 do session:Subscribe("BX","1m");session:RefreshStats()end
 for id in pairs(session.Pending)do assert(before[id])end
 for id in pairs(before)do assert(session.Pending[id])end
end)
session:Destroy()
return results
