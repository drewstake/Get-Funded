-- Matched-state, detached large-order timing. Never touches live accounts or storage.
local H=game:GetService('HttpService');local enabled=H.HttpEnabled;H.HttpEnabled=true
local modules={};local folders={}
for _,variant in ipairs({'baseline','candidate'})do
 local bundle=H:JSONDecode(H:GetAsync('http://127.0.0.1:8818/bundle/'..variant))
 local folder=Instance.new('Folder');folder.Name='DetachedOrderCost_'..variant;folder.Parent=game.ServerStorage;folders[variant]=folder
 for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=folder end
 modules[variant]={CP=require(folder.WorldCheckpoint),C=require(folder.MarketConfig),F=require(folder.FundedAccounts)}
end
local export=H:JSONDecode(H:GetAsync('http://127.0.0.1:8818/checkpoint'));H.HttpEnabled=enabled
local snapshot=modules.baseline.CP.Decode(export.Checkpoint)
task.spawn(function()
 local ok,result=pcall(function()
  local rows={baseline={},candidate={}}
  for i=1,20 do for _,variant in ipairs(i%2==0 and {'candidate','baseline'}or {'baseline','candidate'})do
   local m=modules[variant];local e,p=m.CP.Restore(snapshot,m.C);e:AddAccount('latency:fixed',200000,200,1,true)
   task.wait();local at=os.clock();local accepted,fill=m.F.Perform(e,'latency:fixed',{Action='Place',Contract='BX',Direction=1,Quantity=200,Type='Market',Execution='Immediate'});local orderMs=(os.clock()-at)*1000
   assert(accepted,tostring(fill));task.wait();at=os.clock();local closed=m.F.Perform(e,'latency:fixed',{Action='Close',Contract='BX'});local closeMs=(os.clock()-at)*1000
   assert(closed);local audit=e:Audit();table.insert(rows[variant],{OrderMs=orderMs,CloseMs=closeMs,Filled=fill.Filled,Remaining=fill.Remaining,Hash=audit.Hash,Trades=audit.Trades})
  end end
  for i,a in ipairs(rows.baseline)do local b=rows.candidate[i];assert(a.Hash==b.Hash and a.Trades==b.Trades and a.Filled==b.Filled and a.Remaining==b.Remaining,'Changed fixed-state execution')end
  rows.Scope='20 alternating detached restores per version; same saved state; 200-contract immediate buy and close';rows.Passed=true
  local was=H.HttpEnabled;H.HttpEnabled=true;local posted,err=pcall(function()H:PostAsync('http://127.0.0.1:8818/order-cost.json',H:JSONEncode(rows),Enum.HttpContentType.ApplicationJson)end);H.HttpEnabled=was;assert(posted,err)
 end)
 for _,folder in pairs(folders)do folder:Destroy()end
 if not ok then warn('Detached order cost probe: '..tostring(result))end
end)
return {Started=true,Detached=true,Trials=40}
