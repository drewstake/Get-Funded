import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def edit(name,fn):
 p=source_file(ROOT, f'{name}.luau');s=p.read_text(encoding='utf-8');p.write_text(fn(s),encoding='utf-8')
def sub(s,a,b):
 assert a in s,a[:160]
 return s.replace(a,b)

def progression(s):
 amounts=[250,500,750,750,1000,1000,1000,1250,1500,1500,2000,2000,2500,2500,3000,3500]
 lines=s.splitlines();i=0
 for n,line in enumerate(lines):
  if '{Id=' in line and 'Kind=' in line:
   lines[n]=line.replace(',Name=',f',StartingBonus={amounts[i]},Name=');i+=1
 assert i==16
 return '\n'.join(lines)+'\n'
edit('ProgressionConfig',progression)

def funded(s):
 s=sub(s,'local TradeStats=require(script.Parent.TradeStats)','local TradeStats=require(script.Parent.TradeStats)\nlocal Absence=require(script.Parent.AbsenceSummary)')
 s=sub(s,'m.Goal>0 and m.Title','m.Goal>0 and m.Title and type(m.StartingBonus)=="number" and m.StartingBonus>=0 and m.StartingBonus<1e6 and m.StartingBonus%1==0')
 s=sub(s,'if p and p.Account==a.Id then\n   local earned=', 'if p and p.Account==a.Id then\n   Absence.Closed(p,row)\n   local earned=')
 s=sub(s,' end\n p.Titles=Rules.Titles(p)','  -- Store the amount at first grant: retuning a reward never duplicates or reduces an earned bonus.\n  if p.Awards[m.Id] and p.Awards[m.Id].StartingBonus==nil then\n   p.Awards[m.Id].StartingBonus=m.StartingBonus;self:_touch(p)\n  end\n end\n p.Titles=Rules.Titles(p)')
 s=sub(s,'function Funded:_credits(p)','function Funded:StartingBalance(p)\n local bonus=0;for _,award in pairs(p.Awards or {})do bonus+=award.StartingBonus or 0 end\n return self.Config.StartingBalance+bonus,bonus\nend\nfunction Funded:Depart(uid,now)\n local p=self:Profile(uid);if p then Absence.Depart(self.Engine,p,now or os.time());self:_touch(p)end\nend\nfunction Funded:Return(uid,now)\n local p=self:Profile(uid);if p and p.Absence then Absence.Return(self.Engine,p,now or os.time());self:_touch(p)end\nend\nfunction Funded:AcknowledgeAway(uid,id)\n local p=self:Profile(uid);if not p or not Absence.Acknowledge(p,id)then return false,"Summary already changed."end\n self:_touch(p);return true,"Welcome back."\nend\nfunction Funded:_credits(p)')
 s=sub(s,'archive.Archive.Blown+=1','archive.Archive.Blown+=a.Depleted and 1 or 0')
 s=sub(s,'self:_open(uid,p,self.Config.StartingBalance,"Restart")\n return true,"Account restarted with $10,000. Your ranks, titles and lifetime totals are kept."','self:Evaluate(uid,true)\n self:_open(uid,p,self:StartingBalance(p),"Restart")\n return true,string.format("Account restarted with $%s. Your permanent progress is kept.",self:StartingBalance(p))')
 at='function Funded:Flag(uid,stage)'
 s=sub(s,at,'''-- Discard exposure by transferring its cost basis to an internal clearing account.
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
 self:_archiveRun(uid,p,a);p.Limits.Reset={Tokens=credits-1,At=e.Time}
 self:Evaluate(uid,true)
 self:_open(uid,p,self:StartingBalance(p),"Reset")
 return true,"Account reset. Lifetime statistics, ranks and permanent bonuses are kept."
end
'''+at)
 # Evaluate before archive (Evaluate needs p.Account) and do not grant from removed accounts.
 s=sub(s,'self:_archiveRun(uid,p,a);p.Limits.Reset={Tokens=credits-1,At=e.Time}\n self:Evaluate(uid,true)','self:Evaluate(uid,true)\n self:_archiveRun(uid,p,a);p.Limits.Reset={Tokens=credits-1,At=e.Time}')
 s=sub(s,'self:_archiveRun(uid,p,self.Engine.Accounts[p.Account]);p.Limits.Reset={Tokens=credits-1,At=self.Engine.Time}\n self:Evaluate(uid,true)','self:Evaluate(uid,true)\n self:_archiveRun(uid,p,self.Engine.Accounts[p.Account]);p.Limits.Reset={Tokens=credits-1,At=self.Engine.Time}')
 s=sub(s,'ProtectionPreferences=Protection.Preferences(p.ProtectionPreferences),','StartingBalance=self:StartingBalance(p),StartingBonus=select(2,self:StartingBalance(p)),BaseStartingBalance=self.Config.StartingBalance,AwaySummary=clone(p.AwaySummary),\n  ProtectionPreferences=Protection.Preferences(p.ProtectionPreferences),')
 s=sub(s,'Remaining=math.max(0,goal-value),Earned=p.Awards[m.Id]~=nil,','StartingBonus=p.Awards[m.Id] and p.Awards[m.Id].StartingBonus or m.StartingBonus,\n   Remaining=math.max(0,goal-value),Earned=p.Awards[m.Id]~=nil,')
 return s
edit('FundedAccounts',funded)

def engine(s):
 s=sub(s,'Contract=o.Contract,Direction=p.Direction,Quantity=closed,Entry=p.Entry','PositionId=p.Id,Contract=o.Contract,Direction=p.Direction,Quantity=closed,Entry=p.Entry')
 s=sub(s,'or p.Triggered or not p[field] or a.Locked then','or p.Triggered or a.Locked then')
 s=sub(s,'if not finite(request.ExpectedPrice) or math.abs(request.ExpectedPrice-p[field])>b.Spec.Tick*0.00001 then','local creating=request.Create==true\n if creating and (p[field]~=nil or request.ExpectedPrice~=nil or request.ExpectedQuantity~=p.Quantity)then return false,"Position or protection changed. Please try again."end\n if not creating and (not p[field] or not finite(request.ExpectedPrice) or math.abs(request.ExpectedPrice-p[field])>b.Spec.Tick*0.00001) then')
 s=sub(s,'local distance=(price-last)*p.Direction','if creating then\n  local fromEntry=(price-p.Entry)*p.Direction\n  if field=="Stop" and fromEntry>=0 or field=="Target" and fromEntry<=0 then return false,"Choose the correct side of the entry price."end\n end\n local distance=(price-last)*p.Direction')
 return s
edit('MarketEngine',engine)

def server(s):
 s=sub(s,'funded:Join(state.Uid) funded:Evaluate(state.Uid)','funded:Join(state.Uid) funded:Return(state.Uid) funded:Evaluate(state.Uid)')
 s=sub(s,'Start=true,Restart=true,Flag=true,Stats=true,ProtectionPreferences=true','Start=true,Restart=true,ResetAccount=true,AcknowledgeAway=true,Flag=true,Stats=true,ProtectionPreferences=true')
 s=sub(s,'"Stage","StopOn","TargetOn"','"Stage","StopOn","TargetOn","Create","SummaryId"')
 s=sub(s,'field=="StopOn"or field=="TargetOn"','field=="StopOn"or field=="TargetOn"or field=="Create"')
 s=sub(s,'elseif req.Action=="Flag" then','elseif req.Action=="ResetAccount"then\n  local ok,message=funded:ResetAccount(uid,req.ExpectedAccount)\n  if ok then state.Owner=funded:Owner(uid);state.Full=true;market:SetConnected(state.Owner,true)end\n  reply(state,req.Id,ok,message,nil,{Kind="ResetAccount"});return\n elseif req.Action=="AcknowledgeAway"then\n  local ok,message=funded:AcknowledgeAway(uid,req.SummaryId)\n  reply(state,req.Id,ok,message,nil,{Kind="AcknowledgeAway"});return\n elseif req.Action=="Flag" then')
 s=sub(s,'if market and departing and departing.Owner then market:SetConnected(departing.Owner,false)end','if market and departing and departing.Owner then funded:Depart(departing.Uid);market:SetConnected(departing.Owner,false)end')
 s=sub(s,'-- There is deliberately no reset action on OrderRequest or any client-to-server admin remote.','-- The owner wipe remains separate from the player reset, which preserves lifetime progress.')
 # Shutdown captures disconnect baselines before the frozen world is saved.
 s=sub(s,'game:BindToClose(function()', 'game:BindToClose(function()\n if funded then for _,state in pairs(clients)do funded:Depart(state.Uid)end end')
 return s
edit('MarketServer.server',server)

def client(s):
 s=sub(s,'function Session:Restart() return self:Send("Restart",{}) end','function Session:Restart() return self:Send("Restart",{}) end\nfunction Session:ResetAccount() return self:Send("ResetAccount",{}) end\nfunction Session:AcknowledgeAway(id) return self:Send("AcknowledgeAway",{SummaryId=id})end\nfunction Session:CreateProtection(key,id,field,price,quantity)\n return self:Send("AmendProtection",{Contract=key,OrderId=id,Protection=field,Price=price,Create=true,ExpectedQuantity=quantity})\nend')
 return s
edit('MarketClient',client)
edit('WorldCheckpoint',lambda s:sub(s,'Version=9,Readable={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true}','Version=10,Readable={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}'))
edit('LeaderboardRanking',lambda s:sub(sub(s,'local profit=funded:Earned(p)','local profit=funded.Engine.Accounts[p.Account].Balance'),'Invalid funded profit','Invalid account balance'))
edit('LeaderboardService',lambda s:sub(s,'GetFunded_Leaderboard_v1','GetFunded_BalanceLeaderboard_v1'))
