-- This entire lab stays unparented. Never attach it to the DataModel or replace live modules.
local H=game:GetService('HttpService')
local endpoint='http://127.0.0.1:8836/'
local plan=H:JSONDecode(H:GetAsync(endpoint..'native-plan.json'))
local bundles=H:JSONDecode(H:GetAsync(endpoint..'native-sources.json'))
local lab={Done=false,Phase='Loading',Variant=plan.Variant};_G.DiversityNative=lab
local function build(arm)
 local root=Instance.new('Folder');root.Name='DetachedDiversity'..arm
 local shared=Instance.new('Folder');shared.Name='Shared';shared.Parent=root
 local n=0
 for path,source in pairs(bundles[arm])do
  local m=Instance.new('ModuleScript');m.Name=path:match('/(.+)%.luau$')
  local isShared=path:sub(1,7)=='shared/'
  m.Source=source:gsub('game.ReplicatedStorage.MarketReign%.',isShared and 'script.Parent.'or 'script.Parent.Shared.')
  m.Parent=isShared and shared or root
  n+=1;if n%20==0 then task.wait()end
 end
 return root
end
task.spawn(function()
 local roots={}
 local ok,err=pcall(function()
  for _,arm in ipairs({'Baseline','Candidate'})do
   local root=build(arm);table.insert(roots,root);local CP=require(root.WorldCheckpoint);local C=require(root.Shared.MarketConfig)
   for _,case in ipairs(plan.ParityCases)do
    lab.Phase=arm..' parity '..case
    local e,p=CP.Restore(H:JSONDecode(H:GetAsync(endpoint..'snapshots/normalized-'..case..'.json')),C)
    for i=1,plan.Steps do p:Step();if i%20==0 then task.wait()end end
    local raw=H:JSONEncode(CP.Capture(e,p));local parts=math.ceil(#raw/500000)
    for i=1,parts do H:PostAsync(endpoint..'native/parity-'..arm..'-'..case..'-'..i..'.part',raw:sub((i-1)*500000+1,i*500000),Enum.HttpContentType.TextPlain);task.wait()end
    H:PostAsync(endpoint..'native/parity-'..arm..'-'..case..'-meta.json',H:JSONEncode({Parts=parts,Steps=plan.Steps,Hash=e.TradeHash,Audit=e:Audit()}),Enum.HttpContentType.ApplicationJson)
   end
   local suites={'BotExitRetryTests','BotFairnessTests','BotMomentumTests','BotOrderFlowTests','BotParticipationTests','BotPublicInformationTests','BotRefreshTests','BotSignalsTests','BotWhaleTests','ExecutionChoiceTests','ExecutionIntegrityTests','MakerLiquidityTests','MarketTests','OrderFlowMarketTests','ProtectionScaleTests','ProtectiveOrdersTests','ScalperTests','SecurityTests','SharedDepthTests','TradeLimitsTests','WorldTests'}
   if arm=='Candidate'then table.insert(suites,'BotDiversityTests')end
   for _,name in ipairs(suites)do
    lab.Phase=arm..' '..name;task.wait()
    -- Yield between simulated ticks in the three long-running detached suites.
    -- Their simulation clocks are explicit; parity above uses the unwrapped runtime.
    local P=require(root.Participants);local step=P.Step;local n=0
    if name=='ScalperTests'or name=='WorldTests'or name=='BotDiversityTests'then
     P.Step=function(self,...)
      local result=table.pack(step(self,...));n+=1;if n%40==0 then task.wait()end
      return table.unpack(result,1,result.n)
     end
    end
    local pass,result=pcall(function()return require(root[name]).Run()end)
    P.Step=step
    H:PostAsync(endpoint..'native/'..arm..'-'..name..'.json',H:JSONEncode({Suite=name,Ok=pass,Results=pass and result or tostring(result)}),Enum.HttpContentType.ApplicationJson)
   end
   root:Destroy()
  end
 end)
 for _,root in ipairs(roots)do root:Destroy()end
 lab.Done=true;lab.Ok=ok;lab.Error=not ok and tostring(err)or nil;lab.Phase='Complete'
 H:PostAsync(endpoint..'native/completion.json',H:JSONEncode({Done=lab.Done,Ok=lab.Ok,Error=lab.Error,Variant=lab.Variant}),Enum.HttpContentType.ApplicationJson)
end)
return 'Detached verification started; installed Studio sources unchanged'
