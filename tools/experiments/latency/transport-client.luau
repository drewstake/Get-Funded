local root=game.ReplicatedStorage:WaitForChild('LatencyTransport')
local variant=__VARIANT__
local out=Instance.new('StringValue');out.Name='LatencyTransportResult';out.Parent=game.Players.LocalPlayer.PlayerGui
task.spawn(function()
 local ok,result=pcall(function()
  local session=require(root.MarketClient).New()
  local gui=Instance.new('ScreenGui');gui.Name='DetachedLatencyProbe';gui.ResetOnSpawn=false;gui.Parent=game.Players.LocalPlayer.PlayerGui
  local label=Instance.new('TextLabel');label.Size=UDim2.fromOffset(260,38);label.Position=UDim2.new(0,12,1,-48);label.BackgroundColor3=Color3.fromRGB(17,25,33);label.TextColor3=Color3.new(1,1,1);label.Text='Detached latency measurement';label.TextSize=12;label.Parent=gui
  local received={};local traces={};local displayed={};local waiting={};local tick=session.Quotes.BX and .25 or .25
  local changed=session.Changed.Event:Connect(function()label.Text='Detached probe · '..#session.Orders..' orders · '..tostring(session.SummaryData.Equity)end)
  local replyConnection=session.Replies.Event:Connect(function(reply)
   received[reply.RequestId]=reply
   local now=workspace:GetServerTimeNow();local pending=waiting[reply.RequestId]
   if pending then
    local trace=reply.Trace;local row={Action=pending.Action,SendToReceiveMs=(now-pending.At)*1000,Ok=reply.Ok,
     SendToServerMs=trace and(trace.Received-pending.At)*1000,QueueMs=trace and(trace.Processed-trace.Received)*1000,WorkMs=trace and trace.WorkMs,
     ProcessToReceiveMs=trace and(now-trace.Completed)*1000}
    table.insert(traces,row);label.Text='Detached '..pending.Action..' · '..(reply.Ok and 'confirmed'or 'rejected')
    task.spawn(function()game:GetService('RunService').RenderStepped:Wait();row.SendToDisplayMs=(workspace:GetServerTimeNow()-pending.At)*1000 end)
   end
  end)
  local function send(action,request,noWait)
   local at=workspace:GetServerTimeNow();local accepted,message,_,id=session:Send(action,request)
   assert(accepted,message);waiting[id]={At=at,Action=action}
   if noWait then return id end
   local deadline=os.clock()+5;repeat task.wait()until received[id]or os.clock()>=deadline
   return assert(received[id],'Response timeout')
  end
  for i=1,20 do
   task.wait(.2)
   local quote=session.Quotes.BX;local price=(quote.Bid or quote.Last)-8*tick
   local reply=send('Place',{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=price})
   if reply.Ok and reply.Result.Remaining>0 then
    task.wait(.017+(i%5)*.009)
    send('AmendOrder',{Contract='BX',OrderId=reply.Result.Id,ExpectedPrice=price,ExpectedQuantity=1,Price=price-tick})
    send('Cancel',{OrderId=reply.Result.Id})
   end
  end
  -- Accepted request burst exercises fixed FIFO tails without risking live funds.
  local ids={};for i=1,40 do table.insert(ids,send('Cancel',{OrderId=-i},true))end
  local deadline=os.clock()+5;repeat task.wait()until received[ids[#ids]]or os.clock()>=deadline;assert(received[ids[#ids]],'Burst tail lost')
  task.wait(.25)
  local fill=send('Place',{Contract='BX',Direction=1,Quantity=200,Type='Market',Execution='Immediate'})
  if fill.Ok and(fill.Result.Filled or 0)>0 then send('Close',{Contract='BX'})end
  task.wait(.15);replyConnection:Disconnect();changed:Disconnect();session:Destroy();gui:Destroy()
  return {Passed=true,Variant=variant,Trace=traces,Burst=40,PartialFill=fill.Result,Scope='Production client and engine over detached Studio remotes; rendered test widget'}
 end)
 root.OrderRequest:FireServer({Action='DiagnosticFinish'})
 out.Value=game:GetService('HttpService'):JSONEncode(ok and result or {Passed=false,Error=tostring(result),Variant=variant})
end)
return {Started=true,Variant=variant}
