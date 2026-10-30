-- Read the durable Studio checkpoint and compare its frozen archive with the backup.
local H=game:GetService('HttpService');local base='http://127.0.0.1:8796/'
local root=game.ServerScriptService.MarketReign;local CP=require(root.WorldCheckpoint)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig);local settings=require(root.WorldConfig)
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local record=game:GetService('DataStoreService'):GetDataStore(settings.StoreName,'Studio'):GetAsync(settings.WorldKey)
assert(record.Checkpoint.Version==19,'World has not saved the new format')
local snapshot=CP.Decode(record.Checkpoint);local e,p=CP.Restore(snapshot,C)
local saved=H:JSONDecode(H:GetAsync(base..'studio-checkpoint'));local initial=CP.Decode(saved.Record.Checkpoint)
local prior={};for _,a in ipairs(initial.Engine.Accounts)do prior[a.Id]=a end
local old=CP.Restore(initial,C);equal(old.MarketRetirement,e.MarketRetirement,'archive')
assert(#p.Agents==390 and #e.Config.ContractOrder==3 and #e.MarketRetirement.Accounts==264)
local byMarket={};local closed=0
for _,a in ipairs(p.Agents)do
 local account=e.Accounts[a.Id];local previous=assert(prior[a.Id])
 for _,key in ipairs({'Base','NetCapitalAdjustments','CapitalAdjustments','PnlBaseline'})do equal(previous[key],account[key],key)end
 byMarket[a.Key]=(byMarket[a.Key]or 0)+1;closed+=(account.CompletedTrades or 0)-(previous.CompletedTrades or 0)
end
for _,key in ipairs({'BX','BT','BG'})do assert(byMarket[key]==130)end
for _,o in pairs(e.Orders)do assert(e.Books[o.Contract]and not e.Books[o.Contract].Spec.CloseOnly)end
local plan=require(root.BotRefresh).Prepare(e,p,(p.BotRefreshReceipt and p.BotRefreshReceipt.Sequence or 0)+1,1)
assert(plan.Receipt.Count==390)
local report={At=os.time(),Scope='Studio',Step=e.Step,Time=e.Time,InitialStep=initial.Engine.Step,Version=record.Checkpoint.Version,
 Participants=#p.Agents,ByMarket=byMarket,ArchivedBots=#e.MarketRetirement.Accounts,SettledPositions=#e.MarketRetirement.Settlements,
 CancelledOrders=#e.MarketRetirement.CancelledOrders,ArchiveUnchanged=true,CapitalPreserved=true,FundingEligible=plan.Receipt.Count,
 Audit=e:Audit(),LeaseUntil=record.LeaseUntil,SaveSequence=record.SaveSequence,RawBytes=record.Checkpoint.RawBytes,
 PayloadBytes=#record.Checkpoint.Payload,NewClosingExecutions=closed,Total=require(root.BotStats).Capture(e,p).Total}
local diagnostic=root:FindFirstChild('StudioDiagnostics')
if game:GetService('RunService'):IsRunning()and diagnostic then
 local live=diagnostic:Invoke();report.Mode=live.Mode;report.Status=live.Status;report.RunningStep=live.Step
 report.Performance=diagnostic:Invoke('Performance');report.SessionStartStep=live.Step-report.Performance.Steps
else report.Mode='Stopped';report.Status=record.LeaseUntil==0 and 'Saved and lease released'or 'Lease held'end
report.GameErrors={}
for _,row in ipairs(game:GetService('LogService'):GetLogHistory())do
 if row.messageType==Enum.MessageType.MessageError and(row.message:find('MarketReign')or row.message:find('Get Funded'))then table.insert(report.GameErrors,row.message)end
end
H:PostAsync(base..'playtest-observation.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
return report
