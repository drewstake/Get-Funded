local H=game:GetService('HttpService');local Editor=game:GetService('ScriptEditorService');local History=game:GetService('ChangeHistoryService')
assert(H:JSONDecode(H:GetAsync('http://127.0.0.1:8821/installation-gates-v3.json')).Passed,'Profile correction not verified')
local edits={}
for _,name in ipairs({'MarketConfig','BotMomentum','BotMomentumTests','MakerLiquidityTests'})do
 local parent=name=='MarketConfig'and game.ReplicatedStorage.MarketReign or game.ServerScriptService.MarketReign
 local m=assert(parent:FindFirstChild(name));local oldPath=name=='BotMomentum'and 'original/server/'or 'installed-v2-source/'
 local old=H:GetAsync('http://127.0.0.1:8821/'..oldPath..name..'.luau')
 local desired=H:GetAsync('http://127.0.0.1:8821/candidate-v3/'..name..'.luau')
 local function norm(s)return s:gsub('\r','')end
 assert(norm(m.Source)==norm(old)and norm(Editor:GetEditorSource(m))==norm(old),'Concurrent editor/source change: '..name)
 table.insert(edits,{Name=name,Module=m,Old=old,Desired=desired})
end
for _,edit in ipairs(edits)do H:PostAsync('http://127.0.0.1:8821/pre-profile-fix/'..edit.Name..'.luau',edit.Module.Source,Enum.HttpContentType.TextPlain)end
History:SetWaypoint('Before confirmed Momentum profile bound')
local applied={};local ok,err=pcall(function()
 for _,edit in ipairs(edits)do
  Editor:UpdateSourceAsync(edit.Module,function(current)assert(current:gsub('\r','')==edit.Old:gsub('\r',''),'Concurrent edit');return edit.Desired end)
  table.insert(applied,edit);assert(edit.Module.Source:gsub('\r','')==edit.Desired:gsub('\r',''),'Readback differs')
 end
end)
if not ok then
 for i=#applied,1,-1 do local edit=applied[i];Editor:UpdateSourceAsync(edit.Module,function(current)assert(current:gsub('\r','')==edit.Desired:gsub('\r',''),'Rollback conflict');return edit.Old end)end
 error(err)
end
History:SetWaypoint('Momentum profile bound verified')
local result={Applied=#edits,Checkpoint=28,Momentum=3,Whale=1,MakerPolicy=8,NewsEnabled=false,Published=false}
H:PostAsync('http://127.0.0.1:8821/applied-profile-fix.json',H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
return result
