import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
r=Path(__file__).resolve().parents[2]
for name in ['TradePreferencesTests','SingleAccountTests','OwnerResetTests']:
 p=source_file(r, f'{name}.luau');s=p.read_text(encoding='utf-8')
 s='local Liquidity=require(script.Parent.TestLiquidity)\n'+s
 s=s.replace('e:Submit(', 'Liquidity.Submit(e,').replace('F.Perform(e,','Liquidity.Perform(e,')
 if name=='TradePreferencesTests':
  s=s.replace('   e:ProcessStops();assert(not e.Accounts[id].Positions.BX)','   Liquidity.Offer(e,"BX",side,1,price)\n   e:ProcessStops();assert(not e.Accounts[id].Positions.BX)')
 if name=='SingleAccountTests':
  s=s.replace('b.Last-=800;e:AdvanceClock','b.Last-=800;Liquidity.Offer(e,"BX",1,1,b.Last*b.Spec.Tick);e:AdvanceClock')
  s=s.replace('   p.Triggered="Take profit";table.insert(e.PendingStops,','   Liquidity.Offer(e,market,1,1,p.Target)\n   p.Triggered="Take profit";table.insert(e.PendingStops,')
 p.write_text(s,encoding='utf-8')
p=r/'src/tests/TradeAmendmentTests.luau';s=p.read_text(encoding='utf-8');s='local Liquidity=require(script.Parent.TestLiquidity)\n'+s
s=s.replace(' check(F.Perform(e,a.Id,req(spec.Last+10))',' Liquidity.Offer(e,"BX",-1,3,spec.Last)\n check(F.Perform(e,a.Id,req(spec.Last+10))')
s=s.replace('F.Perform(e,a.Id,{Action="Place"','Liquidity.Perform(e,a.Id,{Action="Place"').replace('F.Perform(e,"other",{Action="Place"','Liquidity.Perform(e,"other",{Action="Place"')
p.write_text(s,encoding='utf-8')
p=r/'src/tests/TradeLimitsTests.luau';s=p.read_text(encoding='utf-8');s='local Liquidity=require(script.Parent.TestLiquidity)\n'+s
s=s.replace('local function submit(e,id,r)local ok,v=e:Submit(id,r)','local function submit(e,id,r)local ok,v=Liquidity.Submit(e,id,r)')
s=s.replace('F.Perform(e,a.Id,','Liquidity.Perform(e,a.Id,')
s=s.replace('    -- Liquidation cancels entries and closes at the market price in one step, off-book.','    -- Post executable exit liquidity; liquidation retries if the book is empty.')
s=s.replace('    e:AdvanceClock(.25)\n    -- Post executable', '    Liquidity.Offer(e,key,side,qty,exit)\n    e:AdvanceClock(.25)\n    -- Post executable')
s=s.replace('assert(e.Books[key].Last==lastTick and e.Books[key].Volume==volume,"Liquidation moved the market price")','assert(e.Books[key].Last==lastTick and e.Books[key].Volume==volume+qty,"Liquidation must consume and print actual exit liquidity")')
start=s.index(' test("A triggered stop fills in full at the market price even when the book is empty')
end=s.index(' test("Triggered stops re-validate',start)
s=s[:start]+''' test("A triggered stop waits for executable liquidity and never fabricates a fill",function()
  local e,a=fresh(Ladder.Tiers[1]);e:AddAccount("taker",1e9,10000,.99,false);local last=Config.Contracts.BX.Last
  local r=request(1,2,last+2,"BX");r.Type="Stop";local armed=submit(e,a.Id,r)
  quote(e,-1,1,last+2,"BX");submit(e,"taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"})
  e:ProcessStops();assert(e.Orders[armed.Id]and not a.Positions.BX,"Empty book fabricated a fill")
  quote(e,-1,2,last+2.25,"BX");e:ProcessStops()
  assert(not e.Orders[armed.Id]and a.Positions.BX.Quantity==2 and a.Triggers[1].Filled==2)
  e:Audit()
 end)
'''+s[end:]
start=s.index(' test("Waiting entries fill at their price regardless of balance')
end=s.index(' test("Invalid, fractional',start)
s=s[:start]+''' test("Waiting player limits execute against incoming quantity and re-check capacity",function()
  local e,a=fresh(Ladder.Tiers[1]);local r=submit(e,a.Id,request(1,5,20480))
  a.Balance=1000;a.Realized=-4000;quote(e,-1,5,20480)
  assert(a.Positions.BT.Quantity==5 and a.Positions.BT.Entry==20480 and not e.Orders[r.Id])
  assert(Liquidity.Perform(e,a.Id,{Action="Close",Contract="BT"}))
  a.Balance=10000;a.Realized=10000-a.Base
  local second=submit(e,a.Id,request(1,8,20470));a.Balance=5000;a.Realized=5000-a.Base
  quote(e,-1,8,20470);assert(not a.Positions.BT and not e.Orders[second.Id],"Waiting entry filled past the cap")
  a.Balance=a.Base;a.Realized=0;e:Audit()
 end)
 test("A marketable player limit consumes finite liquidity and rests its residual",function()
  local e,a=fresh(Ladder.Tiers[1]);quote(e,-1,2,20485.5)
  local r=submit(e,a.Id,request(1,5,20486))
  assert(r.Filled==2 and r.Remaining==3 and r.Average==20485.5)
  assert(#e.Books.BT.Asks==0 and e.Books.BT.Bids[1].Quantity==3 and #e.Trades==1)
  rejected(e,a,request(1,1),0);e:Audit()
 end)
'''+s[end:]
p.write_text(s,encoding='utf-8')
p=r/'src/tests/WorldTests.luau';s=p.read_text(encoding='utf-8').replace('-- Book FIFO belongs to participants; player orders never rest in the book (checked below).','-- Player and participant limits share the same preserved FIFO.')
s=s.replace('saved and saved.Remaining==2 and #r.Books.BX.Bids==0 and r:_restingIndex().BX[saved.Id],"Player limit restored into the book"','saved and saved.Remaining==2 and #r.Books.BX.Bids==1 and r.Books.BX.Bids[1].Orders[1]==saved,"Player limit did not restore into the book"')
p.write_text(s,encoding='utf-8')
p=r/'src/tests/MarketTests.luau';s=p.read_text(encoding='utf-8');start=s.index(' test("Player orders never move the simulated market;');end=s.index(' local passed=0',start)
s=s[:start]+''' test("Player executions consume shared liquidity and join the execution tape",function()
  local e=fresh();e:AddAccount("P",100000,100,.9,true)
  place(e,"A",-1,2,5825);local first=place(e,"P",1,3,5825)
  assert(first.Filled==2 and first.Remaining==1 and e.Books.BX.Bids[1].Quantity==1)
  place(e,"B",-1,1);assert(not e.Orders[first.Id]and e.Accounts.P.Positions.BX.Quantity==3)
  assert(e.TotalVolume==3 and #e.Trades==2 and e.Trades[1].Buyer=="P")
  assert(not e.Accounts[Engine.HouseId],"Player fill used a synthetic house counterparty")
  return e:Audit()
 end)
'''+s[end:];p.write_text(s,encoding='utf-8')
print('Account/profile fixtures now provide explicit finite liquidity; obsolete off-book assertions replaced.')
