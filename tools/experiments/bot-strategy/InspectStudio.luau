-- Read-only observer of the running world's latest durable Studio checkpoint.
local H=game:GetService('HttpService');local root=game.ServerScriptService.MarketReign
local CP=require(root.WorldCheckpoint);local Stats=require(root.BotStats)
local settings=require(root.WorldConfig);local config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local record=game:GetService('DataStoreService'):GetDataStore(settings.StoreName,'Studio'):GetAsync(settings.WorldKey)
local e,p=CP.Restore(CP.Decode(record.Checkpoint),config);local base='http://127.0.0.1:8798/'
local saved=H:JSONDecode(H:GetAsync(base..'checkpoint'))
local initial=CP.Decode(saved.Record.Checkpoint)
local prior={};for _,a in ipairs(initial.Engine.Accounts)do prior[a.Id]=a end
local e0,p0=CP.Restore(initial,require(game.ReplicatedStorage.MarketReign.MarketConfig))
local before=Stats.Capture(e0,p0);local current=Stats.Capture(e,p)
local report={At=os.time(),Scope='Studio',Step=e.Step,Time=e.Time,InitialStep=initial.Engine.Step,InitialTime=initial.Engine.Time,
 Version=record.Checkpoint.Version,SignalsVersion=e.Config.BotSignals.Version,Participants=#p.Agents,Total=current.Total,
 Kinds={},Signals={},Audit=e:Audit(),LeaseUntil=record.LeaseUntil,SaveSequence=record.SaveSequence}
local diagnostic=root:FindFirstChild('StudioDiagnostics')
if game:GetService('RunService'):IsRunning()and diagnostic then
 local live=diagnostic:Invoke();report.Mode=live.Mode;report.Status=live.Status;report.RunningStep=live.Step
 report.Performance=diagnostic:Invoke('Performance')
else report.Mode='Stopped';report.Status=record.LeaseUntil==0 and 'Saved and lease released'or 'Lease held'end
for kind,row in pairs(current.Kinds)do
 report.Kinds[kind]={PnlChange=row.Pnl-before.Kinds[kind].Pnl,CompletedTrades=0,BotsTraded=0,Count=row.Count,Active=row.Active,Positions=row.Positions}
end
for _,a in ipairs(p.Agents)do
 local account=e.Accounts[a.Id];local old=assert(prior[a.Id],'Unexpected new bot account')
 assert(account.Base==old.Base and account.NetCapitalAdjustments==old.NetCapitalAdjustments,'Bot capital changed')
 assert(account.PnlBaseline==old.PnlBaseline,'Bot performance reset')
 local count=(account.CompletedTrades or 0)-(old.CompletedTrades or 0)
 local row=report.Kinds[a.Kind];row.CompletedTrades+=count;if count>0 then row.BotsTraded+=1 end
end
for key,m in pairs(p.Markets)do if not e.Books[key].Spec.CloseOnly then
 local history=m.SignalHistory or {};local last=history[#history]
 report.Signals[key]={Samples=#history,LatestAge=last and e.Time-last.Time,Span=#history>0 and last.Time-history[1].Time or 0}
end end
report.CapitalPreserved=true;report.PerformanceBaselinesPreserved=true
local json=H:JSONEncode(report);H:PostAsync(base..'playtest-observation.json',json,Enum.HttpContentType.ApplicationJson)
return report
