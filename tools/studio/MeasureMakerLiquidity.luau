-- Run against isolated MakerQA modules. Probe trades execute only in disposable checkpoint copies.
local shared=game.ReplicatedStorage.MakerQAShared
local server=game.ServerScriptService.MakerQAServer
local E=require(server.MarketEngine)
local Checkpoint=require(server.WorldCheckpoint)
local function clone(v)
 if type(v)~="table"then return v end
 local out={}for k,x in pairs(v)do out[k]=clone(x)end return out
end
local results={}
for _,seed in ipairs({73521,5501,4407})do
 for _,variant in ipairs({"Before","After"})do
  local config=clone(require(variant=="Before" and shared.MarketConfigBefore or shared.MarketConfig))
  local P=require(variant=="Before" and server.ParticipantsBefore or server.Participants)
  local e=E.new(config,seed);local p=P.new(e)
  local row={Seed=seed,Variant=variant,ProbeCount=0,FullFills=0,FilledContracts=0,RequestedContracts=0,Probes={},
   Samples=0,MissingSides=0,DepthSum=0,SpreadSum=0,TwoSided=0,CpuSeconds=0}
  for step=1,4800 do
   local start=os.clock();p:Step();row.CpuSeconds+=os.clock()-start
   if step%20==0 then
    for _,key in ipairs(config.ContractOrder)do
     local b=e.Books[key];e:_pruneBook(b)
     row.Samples+=1
     if #b.Bids>0 and #b.Asks>0 then row.SpreadSum+=b.Asks[1].Price-b.Bids[1].Price;row.TwoSided+=1 end
     for _,side in ipairs({b.Bids,b.Asks})do
      if #side==0 then row.MissingSides+=1 end
      for i=1,math.min(3,#side)do row.DepthSum+=side[i].Quantity end
     end
    end
   end
   if step%2400==0 then
    local snapshot=Checkpoint.Capture(e,p)
    for _,key in ipairs(config.ContractOrder)do for _,side in ipairs({1,-1})do
     local probe=Checkpoint.Restore(snapshot,config)
     probe:AddAccount("liquidity-probe",250000,250,.8,true)
     local ok,fill=probe:Submit("liquidity-probe",{Contract=key,Direction=side,Quantity=143,Type="Market"})
     assert(ok,tostring(fill));probe:Audit()
     row.ProbeCount+=1;row.RequestedContracts+=143;row.FilledContracts+=fill.Filled
     if fill.Filled==143 then row.FullFills+=1 end
     table.insert(row.Probes,{Time=e.Time,Contract=key,Direction=side,Regime=p.Regime.Name,
      Filled=fill.Filled,Cancelled=fill.Cancelled,SlippageTicks=fill.Slippage/config.Contracts[key].Tick})
    end end
   end
   if step%400==0 then task.wait()end
  end
  row.MeanTopThreeDepthPerSide=row.DepthSum/(row.Samples*2)
  row.MeanSpreadTicks=row.SpreadSum/math.max(1,row.TwoSided)
  row.MillisecondsPerStep=row.CpuSeconds/4800*1000
  row.Trades=e.NextTrade;row.Volume=e.TotalVolume
  row.Audit=e:Audit()
  table.insert(results,row)
 end
end
return results
