-- Detached modules and a read-only saved-world copy. No installed source or datastore writes.
local H=game:GetService('HttpService');local base='http://127.0.0.1:8807/'
local function post(name,data)H:PostAsync(base..name,H:JSONEncode(data),Enum.HttpContentType.ApplicationJson)end
local function source(s)return(s:gsub('require%(game%.ReplicatedStorage%.MarketReign%.(%w+)%)','require(script.Parent.%1)'):gsub('require%(game%.ServerScriptService%.MarketReign%.(%w+)%)','require(script.Parent.%1)'))end
local function equal(a,b)
 assert(type(a)==type(b),'Different types')
 if type(a)~='table'then assert(a==b,'Different state');return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Unexpected key '..tostring(k))end
end
task.spawn(function()
 local root=Instance.new('Folder');root.Name='DetachedOrderDrivenValidation'
 local gui;local report={Total=0,Failures=0,Suites={},Detached=true,DataStoreWrites=false}
 local ok,err=xpcall(function()
  for _,container in ipairs({game.ServerScriptService.MarketReign,game.ReplicatedStorage.MarketReign})do
   for _,m in ipairs(container:GetChildren())do if m:IsA('ModuleScript')then
    assert(not root:FindFirstChild(m.Name),'Duplicate module')
    local copy=Instance.new('ModuleScript');copy.Name=m.Name;copy.Source=source(m.Source);copy.Parent=root
   end end;task.wait()
  end
  local release=H:JSONDecode(H:GetAsync(base..'release'))
  for path,item in pairs(release)do if item.ClassName=='ModuleScript'then
   local name=path:match('[^.]+$');local m=root:FindFirstChild(name)or Instance.new('ModuleScript')
   m.Name=name;m.Source=source(item.Source);m.Parent=root
  end end
  for _,name in ipairs({'OrderFlowMarketTests','BotPublicInformationTests','SharedDepthTests','BotFairnessTests','BotSignalsTests','ScalperTests','BotPopulationTests','BotRefreshTests','BotStatsTests','BotExitRetryTests','MakerLiquidityTests','ExecutionIntegrityTests','MarketTests','WorldTests','ProtectiveOrdersTests'})do
   task.wait();local good,rows=pcall(function()return require(root[name]).Run()end)
   rows=good and(rows.Results or rows)or{{Name='Suite',Passed=false,Detail=tostring(rows)}};report.Suites[name]=rows
   for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
   post('studio-progress.json',{Suite=name,Total=report.Total,Failures=report.Failures})
  end
  assert(report.Failures==0,'Native regression failures')
  local CP=require(root.WorldCheckpoint);local C=require(root.MarketConfig)
  local record=H:JSONDecode(H:GetAsync(base..'checkpoint')).Record
  if record then
   local saved=CP.Decode(record.Checkpoint);local e,p=CP.Restore(saved,C)
   local before=CP.Capture(e,p);p:Prepare();local after=CP.Capture(e,p)
   assert(before.Engine.NextTrade==after.Engine.NextTrade and before.Engine.TotalVolume==after.Engine.TotalVolume)
   for i,ac in ipairs(after.Engine.Accounts)do local old=before.Engine.Accounts[i];assert(ac.Id==old.Id and ac.Balance==old.Balance and ac.Base==old.Base and ac.Realized==old.Realized);equal(ac.Positions,old.Positions)end
   p:Prepare();equal(after,CP.Capture(e,p))
   local e2,p2=CP.Restore(CP.Decode(CP.Encode(after)),C);equal(after,CP.Capture(e2,p2))
   for i=1,240 do p:Step();p2:Step();if i%20==0 then task.wait()end end
   equal(CP.Capture(e,p),CP.Capture(e2,p2))
   report.SavedWorld={FromVersion=saved.Version,ToVersion=CP.Version,ReplaySteps=240,Accounts=#e.AccountOrder,Participants=#p.Agents,Audit=e:Audit(),CapitalAndPositionsPreserved=true}
  end
  local Banner=require(root.MarketEventBanner)
  gui=Instance.new('ScreenGui');gui.Name='OrderDrivenBannerValidation';gui.Parent=game:GetService('CoreGui')
  local holder=Instance.new('Frame');holder.BackgroundTransparency=1;holder.Parent=gui
  local plot=Instance.new('Frame');plot.BackgroundTransparency=1;plot.Size=UDim2.fromScale(1,1);plot.Parent=holder
  report.Banners={}
  for _,width in ipairs({390,844,1280})do
   holder.Size=UDim2.fromOffset(width,500);local banner=Banner.new(holder);task.wait(.1)
   for _,direction in ipairs({1,-1})do
    local event={Id='BX:'..width..':'..direction,Contract='BX',Direction=direction,ExpiresAt=100}
    assert(banner:Update(event,10,true,1,'BX'));banner:Step(plot,true,true,2);task.wait(.05)
    assert(banner.Title.Text==(direction==1 and 'MARKET SURGE'or'MARKET SELLOFF'))
    assert(banner.Subtitle.Text==(direction==1 and'Recent upward price move'or'Recent downward price move'))
    assert(banner.Title.TextFits and banner.Subtitle.TextFits and(not banner.Tag.Visible or banner.Tag.TextFits),'Clipped visible banner')
    assert(not banner:Update(event,11,true,3,'BX'),'Duplicate replay')
    assert(not banner:Update(event,11,true,3,'BT')and not banner.Group.Visible,'Wrong instrument remained visible')
    table.insert(report.Banners,{Width=width,Direction=direction})
   end
   banner:Destroy()
  end
 end,debug.traceback)
 if gui then gui:Destroy()end;root:Destroy();report.Success=ok;report.Error=not ok and tostring(err)or nil
 post('studio-validation.json',report)
end)
return 'Detached V22 validation started'
