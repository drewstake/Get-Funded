-- Fresh module graph: never loads or changes the saved exchange.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="TradePreferencesQA";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="TradePreferencesQA";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do
 if m:IsA("LuaSourceContainer")then
  m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.TradePreferencesQA")
   :gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.TradePreferencesQA")
 end
end end
local ok,result=xpcall(function()
 local report={}
 for _,name in ipairs({"TradePreferencesTests","SingleAccountTests","TradeLimitsTests","TradeAmendmentTests","SecurityTests","WorldTests","MarketTests"})do
  local suite=require(server[name]);report[name]=type(suite)=="function"and suite()or suite.Run()
 end
 for _,name in ipairs({"ChartViewportTests","ChartToolsTests","ChartPaintPoolTests"})do report[name]=require(shared[name])()end
 local h=game:GetService("HttpService");h:PostAsync("http://127.0.0.1:8775/results/regression-tests.json",h:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
 return report
end,debug.traceback)
shared:Destroy();server:Destroy();assert(ok,result);return result
