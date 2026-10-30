-- Studio Edit only. Builds the current UI from an isolated exchange; no DataStores or remotes.
-- The previous preview stays visible until the replacement has rendered successfully.
local RunService=game:GetService("RunService")
assert(RunService:IsStudio() and not RunService:IsRunning(),"Refresh the preview in Edit mode")
local gui=assert(game.StarterGui:FindFirstChild("MarketReign"),"Missing game GUI")
local modules=Instance.new("Folder") -- Detached: temporary source is never part of a cloud save.
modules.Name="DetachedPreviewModules"
local host,controller,replacement
local ok,result=pcall(function()
 for _,folder in ipairs({game.ReplicatedStorage.MarketReign,game.ServerScriptService.MarketReign})do
  for _,source in ipairs(folder:GetChildren())do
   if source:IsA("ModuleScript")then
    assert(not modules:FindFirstChild(source.Name),"Duplicate module "..source.Name)
    local copy=source:Clone()
    copy.Source=copy.Source:gsub("game%.ReplicatedStorage%.MarketReign","script.Parent")
     :gsub("game%.ServerScriptService%.MarketReign","script.Parent")
    copy.Parent=modules
   end
  end
  task.wait()
 end
 local Config=require(modules.MarketConfig)
 local Engine=require(modules.MarketEngine)
 local Participants=require(modules.Participants)
 local engine=Engine.new(Config,Config.Seed~=0 and Config.Seed or 73521)
 local population=Participants.new(engine)
 -- Fill the initial chart even when its default tier uses a longer stored series.
 local default=require(modules.ChartTimeframes).Default
 local seconds=0;for _,tf in ipairs(Config.Timeframes)do if tf[1]==default then seconds=tf[2]end end
 assert(seconds>0,"Missing default preview timeframe")
 local steps=math.floor(math.max(Config.WarmupSeconds,seconds*40)/Config.StepSeconds)
 for i=1,steps do
  population:Step()
  if i%40==0 then task.wait()end -- Keep Studio responsive during market-history generation.
 end
 local ladder=require(modules.ProgressionConfig)
 local funded=require(modules.FundedAccounts).new(engine,ladder,Config)
 funded:Start("preview") funded:Flag("preview","TutorialDone")
 local owner=funded:Owner("preview")
 local snapshot=engine:Snapshot(owner,"BX","1m",true)
 snapshot.CandlesBySeries={}
 for _,key in ipairs(Config.ContractOrder) do
  for _,tf in ipairs(Config.Timeframes) do snapshot.CandlesBySeries[key..":"..tf[1]]=engine:Snapshot(owner,key,tf[1],true).Candles end
 end
 host=Instance.new("Frame");host.Name="PreviewBuildStaging";host.Size=UDim2.fromScale(1,1)
 host.BackgroundTransparency=1;host.Visible=false;host.Parent=gui
 task.wait()
 controller=require(modules.TerminalUI).Mount(host,{Preview=true,PreviewData=snapshot,PortfolioData=funded:View("preview")})
 task.wait();task.wait() -- Let native AbsoluteSize/layout settle before freezing the hierarchy.
 local count=0
 for _,object in ipairs(controller.Root.Canvas.Chart.CandlestickPlot:GetDescendants()) do if object.Name=="Candle" and object.Visible then count+=1 end end
 assert(count>0,"Preview requires executed trades")
 assert(not controller.Root:FindFirstChild("Waiting",true),"Preview unexpectedly empty")
 replacement=controller.Root:Clone() -- Persist native objects, not controller connections.
 replacement:SetAttribute("PreviewSourceVersion",require(modules.WorldCheckpoint).Version)
 local result={Candles=count,Seed=engine.Seed,Executions=engine.NextTrade,Audit=engine:Audit(),
  PreviewSourceVersion=replacement:GetAttribute("PreviewSourceVersion"),Instances=#replacement:GetDescendants(),
  Viewport=tostring(controller.Root.AbsoluteSize),DataStoreWrites=0}
 controller:Destroy();controller=nil
 host:Destroy();host=nil
 local old=gui:FindFirstChild("Workspace")
 replacement.Parent=gui
 if old then old:Destroy()end
 replacement=nil
 return result
end)
if controller then controller:Destroy()end
if host then host:Destroy()end
if replacement then replacement:Destroy()end
modules:Destroy()
if not ok then error(result) end
return result
