local fs=require('@lune/fs');local serde=require('@lune/serde');local process=require('@lune/process')
local variant=process.args[1]or 'candidate';local seed=tonumber(process.args[2])or 19381
local seconds=tonumber(process.args[3])or 7200
local E=require('./'..variant..'/MarketEngine');local P=require('./'..variant..'/Participants')
local C=require('./'..variant..'/MarketConfig')
local function clone(x)if type(x)~='table'then return x end;local y={}for k,v in pairs(x)do y[k]=clone(v)end;return y end
local c=clone(C);c.MaxTradeHistory=100;c.MaxOrderHistory=100;c.MaxAccountHistory=5;c.MaxCandles=200
local e=E.new(c,seed);local p=P.new(e);local agents,groups={},{}
for _,a in ipairs(p.Agents)do
 agents[a.Id]=a
 groups[a.Kind]=groups[a.Kind]or {Bots=0,Positive=0,Negative=0,Depleted=0,Paused=0,Pnl=0,MinReturn=1,
  Closes=0,Wins=0,Losses=0,ClosedContracts=0,FillContracts=0,PassiveContracts=0,UnprotectedSamples=0}
end
local activeTrade;local trade=e._trade
e._trade=function(self,b,incoming,resting,qty)
 activeTrade={Incoming=incoming,Resting=resting};local result=trade(self,b,incoming,resting,qty);activeTrade=nil;return result
end
local fill=e._fillAccount
e._fillAccount=function(self,o,price,qty,id)
 local a=agents[o.Owner];local ac=self.Accounts[o.Owner];local pos=ac.Positions[o.Contract]
 local closed=pos and pos.Direction~=o.Direction and math.min(qty,pos.Quantity)or 0
 local before=ac.Realized;local result=fill(self,o,price,qty,id)
 if a then
  local g=groups[a.Kind];g.FillContracts+=qty
  if activeTrade and activeTrade.Resting==o then g.PassiveContracts+=qty end
  if closed>0 then g.Closes+=1;g.ClosedContracts+=closed
   local pnl=ac.Realized-before;if pnl>.005 then g.Wins+=1 elseif pnl<-.005 then g.Losses+=1 end
  end
 end
 return result
end
local clock=os.clock();local samples={};local twoSided,totalSamples=0,0
for step=1,math.floor(seconds/c.StepSeconds)do
 p:Step()
 if step%40==0 then
  for _,key in ipairs(c.ContractOrder)do local b=e.Books[key];totalSamples+=1;if b.Bids[1]and b.Asks[1]then twoSided+=1 end end
  for _,a in ipairs(p.Agents)do local ac=e.Accounts[a.Id];local g=groups[a.Kind]
   g.MinReturn=math.min(g.MinReturn,(e:Summary(ac).Equity-a.Budget)/a.Budget)
   local pos=ac.Positions[a.Key];if pos and not pos.Stop then g.UnprotectedSamples+=1 end
  end
 end
 if step%2400==0 then e:Audit();print(variant,seed,e.Time,math.floor(os.clock()-clock))end
end
local bots={}
for _,a in ipairs(p.Agents)do
 local ac=e.Accounts[a.Id];local s=e:Summary(ac);local pnl=ac.Realized+s.Unrealized;local g=groups[a.Kind]
 g.Bots+=1;g.Pnl+=pnl;if pnl>0 then g.Positive+=1 elseif pnl<0 then g.Negative+=1 end
 if s.Equity<=0 then g.Depleted+=1 end
 if a.Kind=='Liquidity'and c.BotLiquidity and s.Equity<=a.Budget*(1-c.BotLiquidity.MaxDrawdown)then g.Paused+=1 end
 table.insert(bots,{Id=a.Id,Kind=a.Kind,Equity=s.Equity,Pnl=pnl,Contracts=ac.Positions[a.Key]and ac.Positions[a.Key].Quantity or 0})
end
table.sort(bots,function(a,b)return a.Id<b.Id end)
local out={Variant=variant,Seed=seed,Seconds=seconds,Groups=groups,Bots=bots,TwoSidedFraction=twoSided/totalSamples,Audit=e:Audit(),Elapsed=os.clock()-clock}
local path='output/bot-fairness-20261019/'..variant..'-'..seed..'-'..seconds..'.json'
fs.writeFile(path,serde.encode('json',out,true));print('Saved',path)
