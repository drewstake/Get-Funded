-- Run in Edit only after the isolated comparison and verification gates pass.
local H=game:GetService('HttpService')
local Editor=game:GetService('ScriptEditorService')
local History=game:GetService('ChangeHistoryService')
local function normalized(s)return s:gsub('\r','')end
local names={'BotWhale','BotWhaleTests','BotOrderFlow','WorldCheckpoint','MarketConfig','BotOrderFlowTests','BotParticipationTests','OrderFlowMarketTests','BotRefreshTests'}
local edits={}
-- Validate every source before making the first mutation; do not overwrite editor work.
for _,name in ipairs(names)do
 local shared=name=='MarketConfig';local parent=shared and game.ReplicatedStorage.MarketReign or game.ServerScriptService.MarketReign
 local module=parent:FindFirstChild(name)
 local desired=H:GetAsync('http://127.0.0.1:8818/candidate/'..name..'.luau')
 local old
 if name~='BotWhale'and name~='BotWhaleTests'then
  assert(module and module:IsA('ModuleScript'),'Missing original '..name)
  old=H:GetAsync('http://127.0.0.1:8818/original/'..(shared and 'shared'or 'server')..'/'..name..'.luau')
  assert(normalized(module.Source)==normalized(old),'Source changed since export: '..name)
  assert(normalized(Editor:GetEditorSource(module))==normalized(old),'Unsaved editor changes: '..name)
 else assert(not module,'New module already exists: '..name)end
 table.insert(edits,{Name=name,Parent=parent,Module=module,Source=desired,Old=old})
end
for _,edit in ipairs(edits)do if edit.Module then
 H:PostAsync('http://127.0.0.1:8818/pre-apply/'..edit.Name..'.luau',edit.Module.Source,Enum.HttpContentType.TextPlain)
end end
History:SetWaypoint('Before patient Whale execution')
local applied={}
for _,edit in ipairs(edits)do
 local module=edit.Module
 if module then
  Editor:UpdateSourceAsync(module,function(current)
   assert(normalized(current)==normalized(edit.Old),'Concurrent source change: '..edit.Name)
   return edit.Source
  end)
 else
  module=Instance.new('ModuleScript');module.Name=edit.Name;module.Source=edit.Source;module.Parent=edit.Parent
 end
 assert(normalized(module.Source)==normalized(edit.Source),'Readback differs: '..edit.Name)
 table.insert(applied,{Name=edit.Name,Path=module:GetFullName(),Bytes=#module.Source})
end
History:SetWaypoint('Patient Whale execution verified')
H:PostAsync('http://127.0.0.1:8818/applied.json',H:JSONEncode({Files=applied,Checkpoint=27,WhalePolicy=1}),Enum.HttpContentType.ApplicationJson)
return {Applied=#applied,Checkpoint=27,WhalePolicy=1,NewsEnabled=false}
