-- Run in Edit only after the paired comparison, independent tests and safety gates pass.
local H=game:GetService('HttpService');local Editor=game:GetService('ScriptEditorService');local History=game:GetService('ChangeHistoryService')
local gates=H:JSONDecode(H:GetAsync('http://127.0.0.1:8821/installation-gates.json'));assert(gates.Passed,'Candidate did not pass installation gates')
local names={'Participants','WorldCheckpoint','MarketConfig','MakerLiquidityTests','BotMomentumTests','BotOrderFlowTests','BotParticipationTests','BotRefreshTests','BotWhaleTests','OrderFlowMarketTests'}
local function norm(s)return s:gsub('\r','')end
local edits={}
for _,name in ipairs(names)do
 local shared=name=='MarketConfig';local parent=shared and game.ReplicatedStorage.MarketReign or game.ServerScriptService.MarketReign
 local m=assert(parent:FindFirstChild(name));local old=H:GetAsync('http://127.0.0.1:8821/original/'..(shared and 'shared'or 'server')..'/'..name..'.luau')
 local desired=H:GetAsync('http://127.0.0.1:8821/candidate/'..name..'.luau')
 assert(norm(m.Source)==norm(old),'Source changed since inspection: '..name)
 assert(norm(Editor:GetEditorSource(m))==norm(old),'Unsaved editor changes: '..name)
 table.insert(edits,{Name=name,Module=m,Old=old,Desired=desired})
end
for _,edit in ipairs(edits)do H:PostAsync('http://127.0.0.1:8821/pre-apply/'..edit.Name..'.luau',edit.Module.Source,Enum.HttpContentType.TextPlain)end
History:SetWaypoint('Before tested candle-streak correction')
local applied={}
local ok,err=pcall(function()
 for _,edit in ipairs(edits)do
  Editor:UpdateSourceAsync(edit.Module,function(current)assert(norm(current)==norm(edit.Old),'Concurrent edit: '..edit.Name);return edit.Desired end)
  table.insert(applied,edit);assert(norm(edit.Module.Source)==norm(edit.Desired),'Source readback differs: '..edit.Name)
 end
end)
if not ok then
 for i=#applied,1,-1 do local edit=applied[i]
  Editor:UpdateSourceAsync(edit.Module,function(current)assert(norm(current)==norm(edit.Desired),'Concurrent edit blocks rollback: '..edit.Name);return edit.Old end)
 end
 error(err)
end
History:SetWaypoint('Tested candle-streak correction applied')
local result={Applied=#edits,Checkpoint=28,Momentum=2,Whale=1,MakerPolicy=8,NewsEnabled=false,Published=false,Files={}}
for _,edit in ipairs(edits)do table.insert(result.Files,{Name=edit.Name,Path=edit.Module:GetFullName(),Bytes=#edit.Module.Source})end
H:PostAsync('http://127.0.0.1:8821/applied.json',H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
return result
