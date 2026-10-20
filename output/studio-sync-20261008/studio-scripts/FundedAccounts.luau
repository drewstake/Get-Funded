-- Single-account lifecycle; historical module name keeps place references stable.
-- All grants, archives and rewards share the exchange's fenced checkpoint.
local Funded={} Funded.__index=Funded
local Rules=require(game.ReplicatedStorage.MarketReign.ProgressionRules)
local TradeStats=require(script.Parent.TradeStats)
local Absence=require(script.Parent.AbsenceSummary)
local Protection=require(game.ReplicatedStorage.MarketReign.TradeProtection)
local function clone(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=clone(x) end return r end
local function keys(t) local r={} for k in pairs(t or {}) do table.insert(r,k) end table.sort(r) return r end
function Funded.Validate(c)
 assert(c.Version==4 and type(c.StartingBalance)=="number" and c.StartingBalance>0 and c.StartingBalance<math.huge and c.StartingBalance%1==0,"Invalid single-account configuration")
 assert(type(c.MinimumContracts)=="number" and c.MinimumContracts>=1 and c.MinimumContracts<math.huge and c.MinimumContracts%1==0
  and type(c.BalancePerContract)=="number" and c.BalancePerContract>0 and c.BalancePerContract<math.huge,"Invalid contract limit configuration")
 local seen={} for _,m in ipairs(c.Milestones) do assert(not seen[m.Id] and m.Goal>0 and m.Title and type(m.StartingBonus)=="number" and m.StartingBonus>=0 and m.StartingBonus<1e6 and m.StartingBonus%1==0,"Invalid milestone");seen[m.Id]=true end
end
function Funded.Key(uid) return tostring(uid) end
function Funded:Profile(uid) return self.Engine.Profiles[uid] end
function Funded:_touch(p) p.Revision=(p.Revision or 0)+1 end
function Funded:Owner(uid) local p=self:Profile(uid);return p and p.Account end
function Funded:Usable(a) return a and not (a.Locked or a.Depleted or a.Retired or a.LegacyRetired) end
function Funded:_new(uid)
 local p={V=4,Run=0,Ledger={},Tiers={},Awards={},Titles={},Rank="New Trader",Tutorial="Pending",Revision=1,
  Created=self.Engine.Time,Events={},RunHistory={},Limits={}}
 self.Engine.Profiles[uid]=p return p
end
function Funded:_open(uid,p,balance,source)
 p.Run+=1
 local id="player:"..uid..":single:"..p.Run
 assert(not self.Engine.Accounts[id],"Duplicate run identity")
 local a=self.Engine:AddAccount(id,balance,self.Config.MinimumContracts,self.Config.MarginUse,true)
 a.ProfileId=uid;a.Group="player:"..uid;a.SingleAccount=true;a.Run=p.Run
 p.Account=id;p.Active=id;p.RunStartBalance=balance;p.RunSource=source;p.FailureNotice=nil
 p.PendingTradeCloses=nil
 table.insert(p.Ledger,id);self:_touch(p);return a
end
function Funded:CreationAllowed(kind)
 if (self.Capacity and not self.Capacity(kind)) or #self.Engine.AccountOrder>=self.Config.AccountLimits.MaxExchangeAccounts then
  return false,"The exchange is at capacity. Please try again later."
 end
 return true
end
-- Run before the first durable V8 checkpoint, without interleaved client or market steps.
-- Close through Submit so the house counter-entry, cash flow and inventory stay balanced.
function Funded:Migrate(p,uid)
 if p.V==4 then
  assert(p.Account and self.Engine.Accounts[p.Account] and p.Awards and p.Ledger,"Invalid single-account profile")
  self.Engine:ContractLimit(self.Engine.Accounts[p.Account])
  self:Evaluate(uid,true)
  return
 end
 assert((p.V or 1)<4,"Unsupported player profile version")
 local e=self.Engine;local original=clone(p);local ids,seen={},{}
 local function retain(id)
  assert(e.Accounts[id] and e.Accounts[id].Player,"Missing historical player account")
  if not seen[id] then seen[id]=true;table.insert(ids,id) end
 end
 for _,id in ipairs(p.Ledger or {}) do retain(id) end
 local prefix="player:"..uid..":"
 for _,id in ipairs(e.AccountOrder) do if e.Accounts[id].Player and id:sub(1,#prefix)==prefix then retain(id) end end
 local active=(p.Instances or {})[p.Active] or (p.Tiers or {})[p.Active]
 local selected=type(active)=="table" and active.Account or nil
 if not seen[selected] or not self:Usable(e.Accounts[selected]) then
  selected=nil
  for i=#ids,1,-1 do local a=e.Accounts[ids[i]];if self:Usable(a) and not a.Archive then selected=ids[i];break end end
 end
 local evidence={}
 for _,id in ipairs(ids) do
  local a=e.Accounts[id]
  evidence[id]={Base=a.Base,Balance=a.Balance,Realized=a.Realized,Positions=clone(a.Positions),Orders={}}
  for _,orderId in ipairs(keys(a.OpenOrders)) do table.insert(evidence[id].Orders,clone(e.Orders[orderId])) end
  e:CancelAll(id)
  for _,contract in ipairs(keys(a.Positions)) do
   local pos=a.Positions[contract];pos.Stop=nil;pos.Target=nil;pos.Triggered="Single account migration"
   while a.Positions[contract] do
    local held=a.Positions[contract]
    local ok,result=e:Submit(id,{Contract=contract,Direction=-held.Direction,Quantity=math.min(held.Quantity,e.Config.MaxPlayerQuantity),Type="Market",ReduceOnly=true},{AdministrativeSettlement=true})
    assert(ok and result.Filled>0,"Could not settle historical position")
   end
  end
  TradeStats.Reconcile(e,a,os.time());a.Retired=true;a.LegacyRetired=true;a.Locked=true;a.MigrationArchived=true
 end
 local pending={};for _,v in ipairs(e.PendingStops) do if not seen[v.Owner] then table.insert(pending,v) end end;e.PendingStops=pending
 local carry=selected and e.Accounts[selected].Realized or 0
 local balance=selected and self.Config.StartingBalance+carry or (#ids==0 and self.Config.StartingBalance or 0)
 local q=self:_new(uid);q.Ledger=ids;q.LegacyProfile=original
 q.Migration={Version=1,At=e.Time,Selected=selected,CarryProfit=carry,Balance=balance,Accounts=evidence,
  Rule=tostring(self.Config.StartingBalance).." + selected account net result after closing; no combined balances or wallet conversion"}
 q.PlayerName=p.PlayerName;q.DisplayName=p.DisplayName
 q.Awards=clone(original.Awards or {});q.Titles=clone(original.Titles or {})
 for _,tier in ipairs({"F5K","F10K","F25K","F50K","F100K"}) do
  if (original.Tiers or {})[tier] then table.insert(q.Titles,"Legacy "..tier:sub(2).." Trader") end
 end
 if original.Completion then table.insert(q.Titles,"Legacy Top Tier Complete") end
 local a=self:_open(uid,q,balance,"Migration")
 if balance<=0 then a.Locked=true;a.Depleted=true;a.DepletedAt=e.Time end
 -- Carry is capital on the new run. Its profit is already on the old ledger, counted once.
 self:Evaluate(uid,true)
end
function Funded.new(engine,config,market,options)
 Funded.Validate(config);engine.Profiles=engine.Profiles or {}
 local self=setmetatable({Engine=engine,Config=config,Market=market or engine.Config,Capacity=options and options.Capacity},Funded)
 engine.OnFundedClose=nil
 for _,id in ipairs(engine.AccountOrder) do
  local a=engine.Accounts[id];local uid=id:match("^player:([^:]+):")
  if a.Player and uid and not engine.Profiles[uid] then engine.Profiles[uid]={V=1,Tiers={},Ledger={}} end
 end
 for _,uid in ipairs(keys(engine.Profiles)) do self:Migrate(engine.Profiles[uid],uid) end
 engine.OnFundedClose=function(a,row)
  local p=a.ProfileId and self:Profile(a.ProfileId)
  if p and p.Account==a.Id then
   Absence.Closed(p,row)
   local earned=self:Evaluate(a.ProfileId,nil,true)
   -- A position can close across many counterpart fills, orders and server steps.
   -- Keep its result in the checkpointed profile until it is flat (or reverses),
   -- independently of the bounded history and unrelated positions/account profit.
   p.PendingTradeCloses=p.PendingTradeCloses or {}
   local result=p.PendingTradeCloses[row.Contract]
   if not result or result.PositionId~=row.PositionId or result.Direction~=row.Direction then
    result={PositionId=row.PositionId,Direction=row.Direction,Pnl=0,Quantity=0,Rewards={}}
    -- Upgrade older open positions using their retained exits, including this fill.
    for _,exit in ipairs(a.History)do
     if exit.PositionId==row.PositionId and exit.Contract==row.Contract and exit.Direction==row.Direction then
      result.Pnl+=exit.Pnl;result.Quantity+=exit.Quantity
     end
    end
    p.PendingTradeCloses[row.Contract]=result
   else
    result.Pnl+=row.Pnl;result.Quantity+=row.Quantity
   end
   for _,title in ipairs(earned)do table.insert(result.Rewards,title)end
   local held=a.Positions[row.Contract]
   if not held or held.Id~=row.PositionId or held.Direction~=row.Direction then
    local view=self:View(a.ProfileId);p.Events=p.Events or {}
    table.insert(p.Events,{Kind="TradeClosed",Account=a.Id,TradeId=row.TradeId,Reason=row.Reason,
     PositionId=row.PositionId,Contract=row.Contract,Quantity=result.Quantity,
     Pnl=result.Pnl,Balance=a.Balance,Next=view.Next,Run=p.Run,Rewards=result.Rewards})
    while #p.Events>16 do table.remove(p.Events,1) end
    p.PendingTradeCloses[row.Contract]=nil
    if not next(p.PendingTradeCloses)then p.PendingTradeCloses=nil end
   end
   self:_touch(p)
  end
 end
 return self
end
function Funded:Join(uid)
 local p=self:Profile(uid);if not p then self:Start(uid);p=self:Profile(uid) end;return p
end
function Funded:Start(uid)
 if self:Profile(uid) then return true,"Your trading account is ready.",false end
 local ok,reason=self:CreationAllowed("Start");if not ok then return false,reason end
 self:_open(uid,self:_new(uid),self.Config.StartingBalance,"Start")
 self:Evaluate(uid,true)
 return true,"Your $10,000 account is ready. Choose a market to begin.",true
end
-- Only called on a detached checkpoint by the server's owner command. No client action routes here.
-- Remove every historical account as well as the profile so migration cannot resurrect old progress.
function Funded:ResetPlayer(uid)
 local old=self:Profile(uid);assert(old,"No saved player profile")
 local e=self.Engine local ids,removed={},{} local prefix="player:"..uid..":"
 for _,id in ipairs(e.AccountOrder)do
  local a=e.Accounts[id]
  if a.Player and (a.ProfileId==uid or id:sub(1,#prefix)==prefix)then
   removed[id]=true;table.insert(ids,id)
  end
 end
 for _,id in ipairs(old.Ledger)do assert(removed[id],"Profile contains an account owned by another player")end
 assert(removed[old.Account],"Player account is missing")
 local realized,cash=0,0
 for _,id in ipairs(ids)do
  local a=e.Accounts[id];e:CancelAll(id)
  for _,contract in ipairs(keys(a.Positions))do
   local position=a.Positions[contract];position.Stop=nil;position.Target=nil;position.Triggered="Owner reset"
   local ok,fill=e:Submit(id,{Contract=contract,Direction=-position.Direction,Quantity=position.Quantity,Type="Market",ReduceOnly=true},{AdministrativeSettlement=true})
   assert(ok and fill.Filled==position.Quantity and not a.Positions[contract],"Could not settle reset position")
  end
  realized+=a.Realized;cash+=a.CashFlow
 end
 -- Anonymous exchange totals balance the removed ledgers. This is not a player account and stores
 -- no identity, trades, statistics or rewards. Other players and the public market tape stay intact.
 local clearing=e.Accounts["house:reset-clearing"] or e:AddAccount("house:reset-clearing",0,1e9,1,false)
 clearing.House=true;clearing.Balance+=realized;clearing.Realized+=realized;clearing.CashFlow+=cash
 for _,id in ipairs(ids)do e.Accounts[id]=nil end
 for i=#e.AccountOrder,1,-1 do if removed[e.AccountOrder[i]]then table.remove(e.AccountOrder,i)end end
 for i=#e.PendingStops,1,-1 do if removed[e.PendingStops[i].Owner]then table.remove(e.PendingStops,i)end end
 for i=#e.OrderArchive,1,-1 do if removed[e.OrderArchive[i].Owner]then table.remove(e.OrderArchive,i)end end
 local p=self:_new(uid)
 -- Keep only the internal monotonic token: delayed requests from the wiped account must never match.
 p.Run=old.Run;p.PlayerName=old.PlayerName;p.DisplayName=old.DisplayName;p.ProgressionVersion=self.Config.ProgressionVersion
 self:_open(uid,p,self.Config.StartingBalance,"Start");self:Evaluate(uid,true)
 e:Audit()
 return p.Account
end
-- Owner-only capital deposit, called on a detached engine through TransformSaved.
-- Increasing Base with Balance preserves trading P&L and never awards profit titles.
function Funded:GrantMoney(uid,amount,actor,receipt)
 assert(type(amount)=="number"and amount==amount and amount%1==0 and amount>=1 and amount<=1000000000000,"Use a whole-dollar amount from 1 to 1000000000000.")
 assert(type(actor)=="number"and actor>0 and actor%1==0,"Invalid grant issuer")
 assert(type(receipt)=="string"and #receipt>=1 and #receipt<=64,"Invalid grant receipt")
 local p=self:Profile(uid)
 if p then for _,grant in ipairs(p.MoneyGrants or {})do if grant.Id==receipt then
  assert(grant.Amount==amount and grant.Actor==actor,"Grant receipt mismatch");return grant.Balance
 end end end
 if not p then local ok,reason=self:Start(uid);assert(ok,reason);p=self:Profile(uid)end
 local a=self.Engine.Accounts[p.Account]
 assert(self:Usable(a)and not a.Liquidating,"Restart the player's blown account before using /give.")
 assert(a.Base+amount<4e12 and a.Balance+amount<4e12,"Grant would exceed the $4 trillion account balance limit.")
 a.Base+=amount;a.Balance+=amount;a.LossLimit=a.Base;a.Revision+=1
 p.RunStartBalance=(p.RunStartBalance or a.Base-amount)+amount
 self.Engine:ContractLimit(a)
 p.MoneyGranted=(p.MoneyGranted or 0)+amount;p.MoneyGrants=p.MoneyGrants or {}
 table.insert(p.MoneyGrants,{Id=receipt,Actor=actor,Amount=amount,Account=a.Id,Balance=a.Balance,At=os.time()})
 while #p.MoneyGrants>64 do table.remove(p.MoneyGrants,1)end
 self:_touch(p);return a.Balance
end
function Funded:Earned(p)
 local total=0 for _,id in ipairs(p.Ledger) do total+=self.Engine.Accounts[id].Realized end return total
end
function Funded:_counts(p)
 local trades,wins=0,0
 for _,id in ipairs(p.Ledger) do local a=self.Engine.Accounts[id];local s=a.Stats or TradeStats.Reconcile(self.Engine,a,os.time())
  trades+=(s.Trades or 0)+(s.UntrackedTrades or 0);wins+=s.Wins or 0
 end
 return trades,wins
end
function Funded:_metric(p,m,net,trades,wins)
 return Rules.Metric(m,net,trades,wins),m.Goal
end
function Funded:Evaluate(uid,silent,closingTrade)
 local p=self:Profile(uid);if not p then return end
 local a=self.Engine.Accounts[p.Account];assert(a,"Missing single account")
 local migrated=Rules.Normalize(p,self.Engine.Time)
 local net=self:Earned(p);local trades,wins=self:_counts(p)
 p.ProfitHigh=math.max(p.ProfitHigh or 0,net)
 local earned={}
 for _,m in ipairs(self.Config.Milestones)do
  -- Saved high-water profit is authoritative historical evidence for newly introduced titles.
  local value=self:_metric(p,m,migrated and p.ProfitHigh or net,trades,wins)
  if not p.Awards[m.Id] and value+1e-6>=m.Goal then
   p.Awards[m.Id]={At=self.Engine.Time,Net=net,Run=p.Run,Title=m.Title,Goal=m.Goal}
   table.insert(earned,m.Title)
   if not silent and not closingTrade then p.Events=p.Events or {};table.insert(p.Events,{Kind="Milestone",Name=m.Name,Title=m.Title,Id=m.Id})end
   self:_touch(p)
  end
  -- Raise saved rewards to the current bonus once; never stack or reduce earned funds.
  local award=p.Awards[m.Id]
  if award and (award.StartingBonus==nil or award.StartingBonus<m.StartingBonus) then
   award.StartingBonus=m.StartingBonus;self:_touch(p)
  end
 end
 p.Titles=Rules.Titles(p)
 local previous,index=Rules.Rank(p.RankId);index=index or 1
 p.RankAwards=p.RankAwards or {}
 for i,r in ipairs(self.Config.Ranks)do
  if i<=index or Rules.Qualifies(r,migrated and p.ProfitHigh or net,trades,wins)then
   if not p.RankAwards[r.Id]then p.RankAwards[r.Id]={At=self.Engine.Time,Net=net};self:_touch(p)end
   index=math.max(index,i)
  end
 end
 local rank=self.Config.Ranks[index];p.RankId=rank.Id;p.Rank=rank.Name
 if previous and previous.Id~=rank.Id and not silent and not closingTrade then
  p.Events=p.Events or {};table.insert(p.Events,{Kind="RankUp",Id=rank.Id,Name=rank.Name})
 end
 if migrated then self:_touch(p)end
 if a.Depleted and p.FailureNotice~=p.Run then
  p.FailureNotice=p.Run;p.Events=p.Events or {}
  if not silent then table.insert(p.Events,{Kind="Depleted",Tier=a.Id,Event=tostring(p.Run),Name="Trading account"})end
  self:_touch(p)
 end
 return earned
end
function Funded:StartingBalance(p)
 local bonus=0;for _,award in pairs(p.Awards or {})do bonus+=award.StartingBonus or 0 end
 return self.Config.StartingBalance+bonus,bonus
end
function Funded:Depart(uid,now)
 local p=self:Profile(uid);if p then Absence.Depart(self.Engine,p,now or os.time());self:_touch(p)end
end
function Funded:Return(uid,now)
 local p=self:Profile(uid);if p and p.Absence then Absence.Return(self.Engine,p,now or os.time());self:_touch(p)end
end
function Funded:AcknowledgeAway(uid,id)
 local p=self:Profile(uid);if not p or not Absence.Acknowledge(p,id)then return false,"Summary already changed."end
 self:_touch(p);return true,"Welcome back."
end
function Funded:_credits(p)
 local state=p.Limits.Reset or {};local c=self.Config.ResetLimits
 return math.min(c.Burst,(state.Tokens or c.Burst)+math.max(0,self.Engine.Time-(state.At or self.Engine.Time))/(c.RefillSeconds*self.Market.SimulationSpeed))
end
function Funded:CanRestart(p)
 local a=self.Engine.Accounts[p.Account]
 return a.Depleted==true and not next(a.Positions) and not next(a.OpenOrders)
end
-- Completed runs are folded into one accounting record. Legacy migration records remain intact.
function Funded:_archiveRun(uid,p,a)
 assert(not next(a.Positions) and not next(a.OpenOrders),"Cannot archive exposure")
 local id="player:"..uid..":single-history";local archive=self.Engine.Accounts[id]
 if not archive then
  archive=self.Engine:AddAccount(id,0,0,0,true);archive.Retired=true;archive.Locked=true;archive.LegacyRetired=true
  archive.Archive={Attempts=0,Blown=0,Breached=0};table.insert(p.Ledger,id)
 end
 archive.Base+=a.Base;archive.Balance+=a.Balance;archive.Realized+=a.Realized;archive.CashFlow+=a.CashFlow
 archive.Archive.Attempts+=1;archive.Archive.Blown+=a.Depleted and 1 or 0
 archive.CompletedTrades=(archive.CompletedTrades or 0)+(a.CompletedTrades or 0);TradeStats.Merge(archive.Stats,a.Stats)
 for _,row in ipairs(a.History) do table.insert(archive.History,clone(row)) end
 table.sort(archive.History,function(x,y)return x.TradeId>y.TradeId end)
 while #archive.History>self.Engine.Config.MaxAccountHistory do table.remove(archive.History) end
 table.insert(p.RunHistory,1,{Run=p.Run,StartBalance=a.Base,FinalBalance=a.Balance,Net=a.Realized,ClosedAt=self.Engine.Time})
 while #p.RunHistory>32 do table.remove(p.RunHistory) end
 self.Engine.Accounts[a.Id]=nil;table.remove(self.Engine.AccountOrder,table.find(self.Engine.AccountOrder,a.Id))
 table.remove(p.Ledger,table.find(p.Ledger,a.Id))
 local pending={};for _,v in ipairs(self.Engine.PendingStops) do if v.Owner~=a.Id then table.insert(pending,v) end end;self.Engine.PendingStops=pending
end
function Funded:Restart(uid,expected)
 local p=self:Profile(uid);if not p then return false,"Wait for your account to load." end
 if expected~=p.Account then return false,"Your account has changed. Check it before restarting." end
 if not self:CanRestart(p) then return false,"Restart free after your account fails and all positions and orders close." end
 local credits=self:_credits(p)
 if credits<1 then return false,"Restart limit reached. Wait for a restart to become available; your progress is kept." end
 local ok,reason=self:CreationAllowed("Restart");if not ok then return false,reason end
 self:Evaluate(uid,true)
 self:_archiveRun(uid,p,self.Engine.Accounts[p.Account]);p.Limits.Reset={Tokens=credits-1,At=self.Engine.Time}
 self:_open(uid,p,self:StartingBalance(p),"Restart")
 return true,string.format("Account restarted with $%s. Your permanent progress is kept.",self:StartingBalance(p))
end
-- Discard exposure by transferring its cost basis to an internal clearing account.
-- No player fill, completed trade, profit, volume or milestone is generated.
function Funded:ResetAccount(uid,expected)
 local p=self:Profile(uid);if not p then return false,"Wait for your account to load."end
 if expected~=p.Account then return false,"Your account has changed. Check it before resetting."end
 local credits=self:_credits(p);if credits<1 then return false,"Reset limit reached. Please wait before resetting again."end
 local ok,reason=self:CreationAllowed("Reset");if not ok then return false,reason end
 local e=self.Engine;local a=e.Accounts[p.Account]
 e:CancelAll(a.Id)
 local clearing=e.Accounts["house:reset-exposure"] or e:AddAccount("house:reset-exposure",0,1e9,1,false)
 clearing.House=true
 for _,key in ipairs(keys(a.Positions))do
  local pos=a.Positions[key];local spec=e.Books[key].Spec
  local order={Id=0,Owner=clearing.Id,Contract=key,Direction=pos.Direction,Remaining=pos.Quantity,Filled=0,Notional=0,Reference=0}
  e:_fillAccount(order,pos.Entry,pos.Quantity,0)
  a.CashFlow+=pos.Entry*pos.Quantity*pos.Direction*spec.Multiplier
  a.Positions[key]=nil
 end
 p.Absence=nil;p.AwaySummary=nil
 self:Evaluate(uid,true)
 self:_archiveRun(uid,p,a);p.Limits.Reset={Tokens=credits-1,At=e.Time}
 self:_open(uid,p,self:StartingBalance(p),"Reset")
 return true,"Account reset. Lifetime statistics, ranks and permanent bonuses are kept."
end
function Funded:Flag(uid,stage)
 local p=self:Profile(uid);if not p then return false,"Wait for your account to load." end
 if stage~="TutorialDone" and stage~="TutorialSkipped" then return false,"Unknown tutorial step." end
 p.Tutorial=stage=="TutorialDone" and "Done" or "Skipped";self:_touch(p);return true,"Saved."
end
function Funded:TakeEvents(uid)
 local p=self:Profile(uid);if not p or not p.Events or #p.Events==0 then return nil end
 local events=p.Events;p.Events={}
 -- A final fill can enqueue TradeClosed before the engine latches depletion.
 -- Decide at delivery time so the account-failed notice owns that outcome.
 local failed={}
 for _,event in ipairs(events)do if event.Kind=="Depleted"then failed[event.Tier]=true end end
 local visible={}
 for _,event in ipairs(events)do
  local a=event.Account and self.Engine.Accounts[event.Account]
  if event.Kind~="TradeClosed"or not(event.Reason=="Account depleted"or failed[event.Account]or a and a.Depleted)then table.insert(visible,event)end
 end
 return #visible>0 and visible or nil
end
function Funded:SetProtectionPreferences(uid,value)
 local p=self:Profile(uid);if not p then return false,"Wait for your account to load." end
 local nextValue=Protection.ValidatePreferences(value)
 if not nextValue then return false,"Check your stop loss and take profit settings. Use amounts greater than $0." end
 if not p.ProtectionPreferences or not Protection.SamePreferences(p.ProtectionPreferences,nextValue)then
  p.ProtectionPreferences=nextValue;self:_touch(p)
 end
 return true,"Trade protection settings saved."
end
function Funded:View(uid)
 local p=self:Profile(uid);if not p then return {New=true,Revision=0} end
 local a=self.Engine.Accounts[p.Account];local sum=self.Engine:Summary(a);local net=self:Earned(p);local trades,wins=self:_counts(p)
 local failed=a.Depleted==true;local closing=next(a.Positions)~=nil or next(a.OpenOrders)~=nil
 local row={Key=a.Id,Name="Trading account",Short="Trading account",State="Active",Usable=not failed,Depleted=failed,Breached=failed,
  Closing=failed and closing,CanRestart=self:CanRestart(p),DepletionEvent=tostring(p.Run),Balance=a.Balance,Equity=sum.Equity,
  Unrealized=sum.Unrealized,Realized=a.Realized,Limit=self.Engine:ContractLimit(a),Size=a.Base,LossLimit=math.max(0,sum.Equity),Positions=sum.Count}
 local v={Revision=p.Revision,Started=true,Active=a.Id,ActiveName="Trading account",ActiveShort="Trading account",ActiveSize=a.Base,
  Run=p.Run,RunProfit=a.Realized,RunStartBalance=p.RunStartBalance,Earned=net,Open=sum.Unrealized,Balance=a.Balance,Equity=sum.Equity,
  StartingBalance=self:StartingBalance(p),StartingBonus=select(2,self:StartingBalance(p)),BaseStartingBalance=self.Config.StartingBalance,AwaySummary=Absence.WithPnl(self.Engine,clone(p.AwaySummary)),
  ProtectionPreferences=Protection.Preferences(p.ProtectionPreferences),
  Rank=p.Rank,RankId=p.RankId,Trades=trades,Wins=wins,Titles=clone(p.Titles),Awards=clone(p.Awards),Tutorial=p.Tutorial,Accounts={row},CanRestart=row.CanRestart,
  ActiveCount=failed and 0 or 1,UsableCount=failed and 0 or 1,Failed=failed,Milestones={},Migrated=p.Migration~=nil}
 for _,m in ipairs(self.Config.Milestones) do
  local value,goal=self:_metric(p,m,net,trades,wins)
  local r={Key=m.Id,Badge=m.Badge,Name=m.Name,Short=m.Name,Title=m.Title,Kind=m.Kind,Goal=goal,Progress=math.min(value,goal),
   StartingBonus=p.Awards[m.Id] and p.Awards[m.Id].StartingBonus or m.StartingBonus,
   Remaining=math.max(0,goal-value),Earned=p.Awards[m.Id]~=nil,
   EarlierGoal=p.Awards[m.Id]~=nil and p.Awards[m.Id].Goal~=goal}
  table.insert(v.Milestones,r);if not r.Earned and not v.Next then v.Next=clone(r) end
 end
 local rank,index=Rules.Rank(p.RankId)
 v.RankBadge=rank and rank.Badge;v.RankLevel=index;v.RankNext=index and clone(self.Config.Ranks[index+1])
 local _,title=Rules.Titles(p);v.Title=title and title.Title or (#p.Titles>0 and p.Titles[#p.Titles] or "Your first title awaits")
 v.TitleId=title and title.Id;v.TitleBadge=title and title.Badge or 1
 v.Ranks={};for _,r in ipairs(self.Config.Ranks)do local item=clone(r);item.Earned=p.RankAwards[r.Id]~=nil;table.insert(v.Ranks,item)end
 v.Completed=v.Next==nil;return v
end
function Funded:Stats(uid)
 local p=self:Profile(uid);if not p then return {Ready=true,New=true,Scopes={}} end
 local all,current=TradeStats.Empty(),TradeStats.Empty()
 for _,id in ipairs(p.Ledger) do TradeStats.Include(all,self.Engine,self.Engine.Accounts[id]) end
 TradeStats.Include(current,self.Engine,self.Engine.Accounts[p.Account])
 return {Ready=true,Started=true,Run=p.Run,RunStartBalance=p.RunStartBalance,Scopes={
  {Key="ALL",Kind="All",Name="Trading history",Short="Trading history",Life=TradeStats.Finish(all),Current=TradeStats.Finish(current)}}}
end
function Funded:StatsKey(uid)
 local p=self:Profile(uid);if not p then return "new" end
 local a=self.Engine.Accounts[p.Account];return p.Revision..":"..a.Revision..":"..tostring(a.Depleted)
end
function Funded.Perform(engine,owner,req)
 local a=engine.Accounts[owner];if not a then return false,"Unknown account." end
 if req.Action=="Place" then return engine:Submit(owner,req)
 elseif req.Action=="AmendProtection" then return engine:AmendProtection(owner,req)
 elseif req.Action=="AmendOrder" then return engine:AmendOrder(owner,req)
 elseif req.Action=="Cancel" then
  if type(req.OrderId)~="number" then return false,"Unknown order." end
  if req.Protection then return engine:CancelProtection(owner,req.OrderId,req.Protection) end
  return engine:Cancel(owner,req.OrderId)
 elseif req.Action=="Close" then
  local p=a.Positions[req.Contract];if not p then return false,"No open position." end
  engine:CancelAll(owner,req.Contract);p.Triggered="Player close";p.Stop=nil;p.Target=nil
  local ok,result=engine:Submit(owner,{Contract=req.Contract,Direction=-p.Direction,Quantity=engine.Config.PlayerExecution and p.Quantity or math.min(p.Quantity,engine.Config.MaxPlayerQuantity),Type="Market",ReduceOnly=true})
  if ok and result.Remaining>0 and a.Positions[req.Contract]then a.Positions[req.Contract].ExitOrder=result.Id end
  return ok,result
 end
 return false,"Request rejected."
end
function Funded.Describe(result)
 local filled,remaining,cancelled=result.Filled or 0,result.Remaining or 0,result.Cancelled or 0
 local requested=filled+remaining+cancelled
 local prefix=result.Amended and string.format("Limit %s moved to %.2f · ",result.Direction==1 and "Buy"or "Sell",result.Price)or ""
 if result.Queued then return prefix..string.format("Executing %d contracts · %d filled, %d remaining. View or cancel in Orders.",requested,filled,remaining)end
 if cancelled>0 then
  local lead=filled>0 and string.format("Partially filled %d of %d @ %.2f",filled,requested,result.Average) or "No fill"
  return prefix..string.format("%s · %d unfilled contracts cancelled (available liquidity or execution limits).",lead,cancelled)
 elseif filled>0 and remaining>0 then
  return prefix..string.format("Partially filled %d of %d @ %.2f · %d still working.",filled,requested,result.Average,remaining)
 end
 if result.Amended and filled==0 and remaining>0 then return prefix..string.format("No new fills · %d still working.",remaining)end
 return prefix..(filled>0 and string.format("Filled %d @ %.2f",filled,result.Average) or result.Status or "Working")
end
return Funded
