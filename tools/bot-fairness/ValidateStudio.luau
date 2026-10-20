-- Detached copies only: no live module replacement, DataStore write, play/stop or publication.
assert(not game:GetService('RunService'):IsRunning(),'Detached validation requires Edit mode')
local H=game:GetService('HttpService')
local release=H:JSONDecode(H:GetAsync('http://127.0.0.1:8804/release.json'))
local root=Instance.new('Folder');root.Name='DetachedBotFairnessValidation'
local function source(s)
 return(s:gsub('require%(game%.ReplicatedStorage%.MarketReign%.(%w+)%)','require(script.Parent.%1)')
  :gsub('require%(game%.ServerScriptService%.MarketReign%.(%w+)%)','require(script.Parent.%1)'))
end
local report={Total=0,Failures=0,Suites={},Detached=true,DataStoreWrites=false}
local ok,err=xpcall(function()
 for _,container in ipairs({game.ServerScriptService.MarketReign,game.ReplicatedStorage.MarketReign})do
  for _,original in ipairs(container:GetChildren())do if original:IsA('ModuleScript')then
   assert(not root:FindFirstChild(original.Name),'Duplicate module')
   local m=Instance.new('ModuleScript');m.Name=original.Name;m.Source=source(original.Source);m.Parent=root
  end end;task.wait()
 end
 for path,item in pairs(release)do
  local name=path:match('([^.]+)$');local m=root:FindFirstChild(name)or Instance.new('ModuleScript')
  m.Name=name;m.Source=source(item.Source);m.Parent=root
 end
 for _,name in ipairs({'BotPublicInformationTests','BotFairnessTests','BotSignalsTests','ScalperTests','BotStatsTests','MakerLiquidityTests','BotRefreshTests'})do
  task.wait();local good,rows=pcall(function()return require(root[name]).Run()end)
  if not good then rows={{Name='Suite',Passed=false,Detail=tostring(rows)}}end
  rows=rows.Results or rows;report.Suites[name]=rows
  for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
 end
end,debug.traceback)
root:Destroy();report.Success=ok and report.Failures==0;report.Error=not ok and err or nil
return report
