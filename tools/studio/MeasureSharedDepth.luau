-- Offline quote-churn study, run against a source directory with the Lune harness.
local E=require(game.ServerScriptService.MarketReign.MarketEngine)
local P=require(game.ServerScriptService.MarketReign.Participants)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local report={WarmupSimSeconds=300,MeasuredSimSeconds=600,Runs={}}
for _,seed in ipairs({73521,90210,42617})do
 local e=E.new(C,seed);local bots=P.new(e)
 local makers={};for _,a in ipairs(bots.Agents)do if a.Kind=="Maker"then makers[a.Id]=true end end
 for _=1,report.WarmupSimSeconds/C.StepSeconds do bots:Step()end
 local row={Seed=seed,MakerCancellations=0,CancelledAge=0,MakerFills=0,Trades=0,TwoSidedSamples=0,Samples=0}
 local cancel=e.Cancel
 e.Cancel=function(self,owner,id)
  local o=self.Orders[id]
  if o and makers[owner]then row.MakerCancellations+=1;row.CancelledAge+=self.Time-o.Time end
  return cancel(self,owner,id)
 end
 local trade=e._trade
 e._trade=function(self,b,incoming,resting,qty)
  if makers[incoming.Owner]or makers[resting.Owner]then row.MakerFills+=1 end
  row.Trades+=1;return trade(self,b,incoming,resting,qty)
 end
 for step=1,report.MeasuredSimSeconds/C.StepSeconds do
  bots:Step()
  if step%4==0 then for _,key in ipairs(C.ContractOrder)do
   local b=e.Books[key];e:_cleanBook(b);row.Samples+=1
   if #b.Bids>0 and #b.Asks>0 then row.TwoSidedSamples+=1 end
  end end
 end
 row.MeanCancelledAge=row.MakerCancellations>0 and row.CancelledAge/row.MakerCancellations or 0
 row.TwoSidedPercent=100*row.TwoSidedSamples/row.Samples;row.Audit=e:Audit()
 table.insert(report.Runs,row)
end
return report
