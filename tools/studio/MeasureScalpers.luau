-- Isolated simulations only; no live accounts or persistence. Run against the staged QA graph.
local server=game.ServerScriptService.ScalperQAServer
local Default=require(game.ReplicatedStorage.ScalperQAShared.MarketConfig)
local Engine=require(server.MarketEngine)
local Participants=require(server.Participants)
local function clone(v)
 if type(v)~="table"then return v end
 local out={}for k,x in pairs(v)do out[k]=clone(x)end return out
end
local report={}
for _,seed in ipairs({73521,5501,4407})do
 for _,count in ipairs({0,18})do
  local config=clone(Default);config.ScalpersPerInstrument=count
  if config.BotPopulation then config.BotPopulation.Counts.Scalper=count end
  local e=Engine.new(config,seed);local p=Participants.new(e)
  local spreadSum,spreadCount,missing=0,0,0
  local start=os.clock()
  for step=1,7200 do
   p:Step()
   if step%20==0 then
    for _,key in ipairs(config.ContractOrder)do
     local b=e.Books[key];local bid,ask=b.Bids[1],b.Asks[1]
     if bid and ask then spreadSum+=ask.Price-bid.Price;spreadCount+=1 else missing+=1 end
    end
   end
  end
  local elapsed=os.clock()-start
  local candles,wicked,flat,lowVolume,volume,range,closed,locked=0,0,0,0,0,0,0,0
  for _,key in ipairs(config.ContractOrder)do
   local b=e.Books[key];local tick=b.Spec.Tick
   for _,c in ipairs(b.Candles["1m"])do if c.Time<1800 then
    candles+=1;volume+=c.Volume;range+=(c.High-c.Low)/tick
    if c.High>math.max(c.Open,c.Close)+tick*.5 or c.Low<math.min(c.Open,c.Close)-tick*.5 then wicked+=1 end
    if c.High-c.Low<tick*.5 then flat+=1 end
    if c.Volume<=5 then lowVolume+=1 end
   end end
  end
  for _,a in ipairs(p.Agents)do if a.Kind=="Scalper"then
   local account=e.Accounts[a.Id];closed+=account.CompletedTrades or 0
   if account.Locked then locked+=1 end
  end end
  table.insert(report,{Seed=seed,ScalpersPerInstrument=count,Trades=e.NextTrade,Volume=e.TotalVolume,
   Candles=candles,MissingMinutes=90-candles,WickPercent=100*wicked/math.max(1,candles),FlatCandles=flat,
   LowVolumeCandles=lowVolume,MeanCandleVolume=volume/math.max(1,candles),MeanRangeTicks=range/math.max(1,candles),
   MeanSpreadTicks=spreadSum/math.max(1,spreadCount),MissingQuoteSamples=missing,
   ClosedScalperTrades=closed,LockedScalpers=locked,MillisecondsPerStep=elapsed/7200*1000,Audit=e:Audit()})
 end
end
return report
