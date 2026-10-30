-- Detached transport only: no order requests, no access to the live exchange.
local root=game.ReplicatedStorage:WaitForChild('LatencyTransport')
local variant=__VARIANT__
local output=Instance.new('StringValue');output.Name='LatencyQuoteResult';output.Parent=game.Players.LocalPlayer.PlayerGui
task.spawn(function()
 local ok,result=pcall(function()
  local session=require(root.MarketClient).New();local samples={}
  local gui=Instance.new('ScreenGui');gui.Name='DetachedQuoteProbe';gui.Parent=game.Players.LocalPlayer.PlayerGui
  local label=Instance.new('TextLabel');label.Size=UDim2.fromOffset(300,30);label.Position=UDim2.new(0,12,1,-38);label.Text='Detached quote trace';label.Parent=gui
  local connection=root.MarketUpdate.OnClientEvent:Connect(function(packet)
   local received=workspace:GetServerTimeNow()
   local q=session.Quotes.BX
   label.Text='Detached depth '..tostring(q.Bid)..' / '..tostring(q.Ask)
   task.spawn(function()
    game:GetService('RunService').RenderStepped:Wait();local painted=workspace:GetServerTimeNow()
    table.insert(samples,{FirstChangeToDisplayMs=packet.TraceFirstDepth and(painted-packet.TraceFirstDepth)*1000,
     LatestChangeToDisplayMs=packet.TraceLastDepth and(painted-packet.TraceLastDepth)*1000,
     BroadcastToReceiveMs=(received-packet.TraceSent)*1000,ReceiveToRenderMs=(painted-received)*1000})
   end)
  end)
  task.wait(20);connection:Disconnect();session:Destroy();gui:Destroy()
  return {Variant=variant,Samples=samples,Scope='Detached saved-world depth mutation to rendered widget, 10Hz; synchronized-clock estimates'}
 end)
 root.OrderRequest:FireServer({Action='DiagnosticFinish'})
 output.Value=game.HttpService:JSONEncode(ok and result or {Error=tostring(result)})
end)
return {Started=true,Seconds=20,Variant=variant}
