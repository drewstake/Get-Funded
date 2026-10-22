-- Run only in Edit after the user permits ending their current play session.
local H=game:GetService('HttpService');local SE=game:GetService('ScriptEditorService')
assert(not game:GetService('RunService'):IsRunning(),'Install requires Edit mode')
local endpoint='http://127.0.0.1:8837/'
local expected=H:JSONDecode(H:GetAsync(endpoint..'expected-original.json'))
local bundle=H:JSONDecode(H:GetAsync(endpoint..'candidate-bundle.json'))
local validated=H:JSONDecode(H:GetAsync(endpoint..'native-validation.json'))
assert(validated.Ok and validated.Result.Passed,'Native validation required')
local root=game.ReplicatedStorage.MarketReign
assert(not root:FindFirstChild('ChartTimeframes'),'New mapping already exists; inspect before replacing')
local originals={};local names={'ChartView','MarketClient','TerminalUI'}
for _,name in ipairs(names)do
 local m=assert(root:FindFirstChild(name));local source=m.Source;local editor=SE:GetEditorSource(m)
 assert(source:gsub('\r\n','\n')==expected[name..'.luau']and editor:gsub('\r\n','\n')==expected[name..'.luau'],name..' changed since validation')
 originals[name]={Source=source,Editor=editor}
end
-- The backup must be durable on disk before the first source mutation.
H:PostAsync(endpoint..'studio-before-install.json',H:JSONEncode({UTC=os.date('!%Y-%m-%dT%H:%M:%SZ'),Originals=originals,ChartTimeframesExisted=false}),Enum.HttpContentType.ApplicationJson)
local added=Instance.new('ModuleScript');added.Name='ChartTimeframes';added.Source=bundle['ChartTimeframes.luau']
local ok,err=xpcall(function()
 added.Parent=root
 for _,name in ipairs(names)do
  local m=root[name];local value=bundle[name..'.luau']
  SE:UpdateSourceAsync(m,function(current)
   assert(current:gsub('\r\n','\n')==expected[name..'.luau'],name..' editor changed during installation')
   return value
  end)
 end
 for _,name in ipairs({'ChartTimeframes','ChartView','MarketClient','TerminalUI'})do
  local m=root[name];local value=bundle[name..'.luau']
  assert(m.Source:gsub('\r\n','\n')==value and SE:GetEditorSource(m):gsub('\r\n','\n')==value,name..' readback mismatch')
 end
end,debug.traceback)
if not ok then
 local rollback={}
 for _,name in ipairs(names)do
  local restored,reason=pcall(function()
   SE:UpdateSourceAsync(root[name],function(current)
    assert(current:gsub('\r\n','\n')==bundle[name..'.luau']or current:gsub('\r\n','\n')==expected[name..'.luau'],'Concurrent edit; preserve it')
    return originals[name].Editor
   end)
  end)
  rollback[name]={Restored=restored,Error=not restored and tostring(reason)or nil}
 end
 added:Destroy()
 H:PostAsync(endpoint..'install-error.json',H:JSONEncode({Error=err,Rollback=rollback}),Enum.HttpContentType.ApplicationJson)
 error(err)
end
local result={Installed=true,Modules={'ChartTimeframes','ChartView','MarketClient','TerminalUI'},SourceAndEditorExact=true,UTC=os.date('!%Y-%m-%dT%H:%M:%SZ'),Published=false,MarketEngineChanged=false,CheckpointChanged=false}
H:PostAsync(endpoint..'installation.json',H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
return result
