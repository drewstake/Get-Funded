local D={}
function D.Run(root,snapshot)
 local e,p=require(root.WorldCheckpoint).Restore(snapshot,require(root.Shared.MarketConfig))
 local start=math.ceil((e.Time+1200)/60)*60;local finish=start+3600
 local kinds,agents={},{};for _,a in ipairs(p.Agents)do kinds[a.Id]=a.Kind;agents[a.Id]=a end
 local rows={};local old=e._trade
 e._trade=function(self,b,inc,rest,qty)
  local prior=b.Last or b.Reference;local ac=self.Accounts[inc.Owner];local pos=ac.Positions[b.Key]
  local closing=pos and inc.Direction~=pos.Direction
  old(self,b,inc,rest,qty)
  if self.Time<start or self.Time>=finish then return end
  local key=b.Key..':'..math.floor(self.Time/60);local row=rows[key]
  if not row then row={Market=b.Key,Time=math.floor(self.Time/60)*60,Open=prior,Close=b.Last,Flows={},Inventory={}};rows[key]=row end
  row.Close=b.Last
  local a=agents[inc.Owner];local kind=kinds[inc.Owner]or 'Player';local phase=a and(a.Momentum and a.Momentum.Phase or a.Whale and a.Whale.Phase)or ''
  local reason=inc.Protection or (closing and 'Closing'or 'Opening');local label=kind..'/'..reason..'/'..phase
  local f=row.Flows[label]or{Buy=0,Sell=0,Move=0,Trades=0,AbsoluteMove=0};row.Flows[label]=f
  f[inc.Direction==1 and 'Buy'or 'Sell']+=qty;f.Move+=b.Last-prior;f.Trades+=1;f.AbsoluteMove+=math.abs(b.Last-prior)
 end
 while e.Time<finish do
  p:Step()
  if e.Time>=start and e.Step%240==0 then
   for _,a in ipairs(p.Agents)do
    local row=rows[a.Key..':'..math.floor((e.Time-.25)/60)]
    if row then local pos=e.Accounts[a.Id].Positions[a.Key];row.Inventory[a.Kind]=(row.Inventory[a.Kind]or 0)+(pos and pos.Quantity*pos.Direction or 0)end
   end
  end
 end
 local result={};for _,v in pairs(rows)do table.insert(result,v)end;table.sort(result,function(a,b)return a.Time==b.Time and a.Market<b.Market or a.Time<b.Time end)
 return {Rows=result,Audit=e:Audit()}
end
return D
