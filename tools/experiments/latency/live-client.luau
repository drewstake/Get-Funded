local R=game:GetService('RunService');local root=game.Players.LocalPlayer.PlayerGui.MarketReign.Workspace
local remote=game.ReplicatedStorage.MarketReign.MarketUpdate;local received={};local painted={};local pending={};local lastAt;local starts={};local gaps={};local started=os.clock()
local c=remote.OnClientEvent:Connect(function(packet)
 local now=os.clock();local row={Step=packet.Step,At=now,GapMs=lastAt and(now-lastAt)*1000,Bytes=#game:GetService('HttpService'):JSONEncode(packet),SentToReceiveMs=packet.LatencyProbeSent and(workspace:GetServerTimeNow()-packet.LatencyProbeSent)*1000};lastAt=now
 local depth=packet.Quotes and packet.Quotes.BX and packet.Quotes.BX.Depth
 if depth then for _,side in ipairs({'Bids','Asks'})do
  row[side]=#depth[side];row[side..'Status']=depth.Status[side]
  if #depth[side]==0 then if not starts[side]then starts[side]={At=now,Step=packet.Step,Side=side,Status=depth.Status[side]}end
  elseif starts[side]then local gap=starts[side];gap.Ms=(now-gap.At)*1000;table.insert(gaps,gap);starts[side]=nil end
 end end
 table.insert(received,row);if packet.Step then pending[packet.Step]=row end
end)
local f=R.RenderStepped:Connect(function()
 local step=root:GetAttribute('MarketStep');local row=step and pending[step]
 if row then table.insert(painted,(os.clock()-row.At)*1000);pending[step]=nil end
end)
task.delay(90,function()
 c:Disconnect();f:Disconnect()
 local value=Instance.new('StringValue');value.Name='LatencyClientObservation';value.Value=game:GetService('HttpService'):JSONEncode({Seconds=os.clock()-started,Packets=received,ReceiveToUIFrameMs=painted,Gaps=gaps,OpenGaps=starts,Chart=root:GetAttributes()});value.Parent=root
end)
return {ObservingSeconds=90}
