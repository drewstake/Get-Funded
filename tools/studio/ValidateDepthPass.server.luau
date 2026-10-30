-- Disposable ownership race check. Test entitlement instances never touch live players.
local shared=game.ReplicatedStorage.MarketReign
local report={Checks={}}
local function check(name,ok)assert(ok,name);table.insert(report.Checks,name)end
local ok,err=xpcall(function()
 local Access=require(game.ServerScriptService.MarketReign.MarketDepthAccess)
 check("Production pass ID is configured",Access.PassId==2006894567)
 local calls=0;local release=Instance.new("BindableEvent");local player={UserId=123}
 local api={UserOwnsGamePassAsync=function(_,uid,id)
  check("Ownership uses the configured pass",uid==123 and id==2006894567)
  calls+=1
  if calls==1 then release.Event:Wait();return false end
  return true
 end}
 local access=Access.new(nil,api);access:Refresh(player);task.wait()
 check("Pending access stays locked and exposes only the pass ID",not access:Status(player).Allowed and access:Status(player).PassId==2006894567)
 access:Refresh(player,true);release:Fire();task.wait();task.wait()
 check("Purchase verification is not lost during an in-flight query",calls==2 and access:Status(player).Allowed)
 access:Forget(player);release:Destroy()
 local market=game:GetService("MarketplaceService")
 report.Product=market:GetProductInfoAsync(2006894567,Enum.InfoType.GamePass)
 check("Roblox resolves the expected pass",report.Product.TargetId==2006894567 and report.Product.Name=="Market Depth Pro")
end,debug.traceback)
report.Ok=ok;report.Error=not ok and err or nil
local value=Instance.new("StringValue");value.Name="DepthPassServerResult";value.Value=game:GetService("HttpService"):JSONEncode(report);value.Parent=shared
print("DEPTH_PASS_SERVER "..value.Value)
