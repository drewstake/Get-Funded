-- Run through Studio MCP in Edit mode after isolated validation passes.
assert(not game:GetService("RunService"):IsRunning(),"Run in Edit mode")
local H=game:GetService("HttpService");local E=game:GetService("EncodingService")
local bundle=H:JSONDecode(H:GetAsync("http://127.0.0.1:8811/bundle"))
local changes={}
local function hash(s)
 local bytes=E:ComputeStringHash(s:gsub("\r\n","\n"),Enum.HashAlgorithm.Sha256)
 return(bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end))
end
for path,item in pairs(bundle)do
 local parent=game;local parts=string.split(path,".")
 for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),path)end
 local old=parent:FindFirstChild(parts[#parts])
 assert((not old and item.ExpectedHash==false)or(old and hash(old.Source)==item.ExpectedHash),"Concurrent change: "..path)
 assert(hash(item.Source)==item.Hash,"Corrupt source: "..path)
 assert(loadstring(item.Source),"Invalid Luau: "..path)
 table.insert(changes,{Path=path,Parent=parent,Name=parts[#parts],Old=old and old.Source,Object=old,Item=item})
end
game:GetService("ChangeHistoryService"):SetWaypoint("Before market alert bar")
local ok,err=xpcall(function()
 for _,c in ipairs(changes)do
  c.Object=c.Object or Instance.new("ModuleScript");c.Object.Name=c.Name;c.Object.Source=c.Item.Source;c.Object.Parent=c.Parent
 end
end,debug.traceback)
if not ok then
 for _,c in ipairs(changes)do if c.Object then if c.Old then c.Object.Source=c.Old else c.Object:Destroy()end end end
 error(err)
end
local report={Installed={}}
for _,c in ipairs(changes)do assert(hash(c.Object.Source)==c.Item.Hash);report.Installed[c.Path]=c.Item.Hash end
local preview=_G.MarketAlertPreview
if preview then preview.Controller:Destroy();preview.Gui:Destroy();preview.Shared:Destroy();_G.MarketAlertPreview=nil end
game:GetService("ChangeHistoryService"):SetWaypoint("Market alert bar installed")
H:PostAsync("http://127.0.0.1:8811/installed.json",H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
return H:JSONEncode(report)
