-- Run with Lune, then execute either generated file in Studio Edit after installing sources.
local fs=require("@lune/fs")
local setup=[=[
assert(not game.ReplicatedStorage:FindFirstChild("DepthSpamShared"),"Depth test already staged")
assert(not game.ServerScriptService:FindFirstChild("DepthSpamServer"),"Depth test already staged")
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="DepthSpamShared";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="DepthSpamServer"
for _,m in ipairs(server:GetDescendants())do if m:IsA("BaseScript")then m.Enabled=false end end
server.Parent=game.ServerScriptService
for _,f in ipairs({shared,server})do for _,m in ipairs(f:GetDescendants())do if m:IsA("LuaSourceContainer")then
 m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.DepthSpamShared")
  :gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.DepthSpamServer")
end end end
local ok,result=pcall(function()
]=]
local cleanup=[=[
end)
shared:Destroy();server:Destroy()
if not ok then error(result)end
return result
]=]
fs.writeDir("tmp/depth-spam")
for _,case in ipairs({
 {"server","tools/studio/ValidateDepthSpam.luau","src/server/MarketServer.server.luau","SERVER"},
 {"client","tools/studio/ValidateDepthSpamClient.luau","src/shared/MarketClient.luau","CLIENT"},
})do
 local source=fs.readFile(case[3])
 local code=fs.readFile(case[2]):gsub("%-%- INSERT_"..case[4].."_SOURCE",function()return source end)
 local path="tmp/depth-spam/"..case[1]..".luau"
 fs.writeFile(path,setup..code.."\n"..cleanup)
 print(path)
end
