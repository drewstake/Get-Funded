from pathlib import Path
p=Path(__file__).resolve().parents[2]/'src/tests/SecurityTests.luau'
s=p.read_text(encoding='utf-8');a=s.index(' test("S1:');b=s.index('\n return report',a)
s=s[:a]+''' test("S1: missing liquidity never fabricates fills, balances, or round-trip profit",function()
  for _,side in ipairs({1,-1})do
   local e,f=exchange(nil,"q1");e:AddAccount("maker",1000000,500,.8,false)
   local id=f:Owner("q1");local b=e.Books.BX;local tick=b.Spec.Tick;local last=b.Last or b.Reference
   assert(e:Submit("maker",{Contract="BX",Direction=side,Quantity=10,Type="Limit",Price=(last+side)*tick}))
   local start=e.Accounts[id].Balance
   for _=1,10 do
    local ok,fill=F.Perform(e,id,{Action="Place",Contract="BX",Direction=side,Quantity=5,Type="Market"})
    assert(ok and fill.Filled==0 and fill.Cancelled==5 and not e.Accounts[id].Positions.BX)
    assert(not F.Perform(e,id,{Action="Close",Contract="BX"}))
   end
   assert(e.Accounts[id].Balance==start and e.TotalVolume==0 and not e.Accounts[E.HouseId])
   local ok,rest=F.Perform(e,id,{Action="Place",Contract="BX",Direction=side,Quantity=1,Type="Limit",Price=last*tick})
   assert(ok and rest.Filled==0 and rest.Remaining==1);e:Cancel(id,rest.Id);e:Audit()
  end
  local e,f=exchange(nil,"depletion");local id=f:Owner("depletion");local b=e.Books.BX
  e:AddAccount("maker",1e9,10000,.99,false)
  assert(e:Submit("maker",{Contract="BX",Direction=-1,Quantity=2,Type="Limit",Price=6000}))
  assert(F.Perform(e,id,{Action="Place",Contract="BX",Direction=1,Quantity=2,Type="Market"}))
  b.Last=math.round(5900/b.Spec.Tick);e:AdvanceClock(.25)
  assert(e.Accounts[id].Locked and e.Accounts[id].Positions.BX.Triggered=="Account depleted")
  assert(e.Accounts[id].Positions.BX.Quantity==2,"Empty book fabricated a liquidation")
  assert(e:Submit("maker",{Contract="BX",Direction=1,Quantity=2,Type="Limit",Price=5900}))
  e:AdvanceClock(.25);assert(not e.Accounts[id].Positions.BX);e:Audit()
  local e2,f2=exchange(nil,"spread");local id2=f2:Owner("spread");local b2=e2.Books.BX;local ref=b2.Reference
  for i,side in ipairs({1,-1})do
   e2:AddAccount("maker"..i,1e9,10000,.99,false)
   assert(e2:Submit("maker"..i,{Contract="BX",Direction=side,Quantity=5,Type="Limit",Price=(ref-side*2)*b2.Spec.Tick}))
  end
  local _,buy=F.Perform(e2,id2,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"})
  local _,sell=F.Perform(e2,id2,{Action="Close",Contract="BX"})
  equal(buy.Average,(ref+2)*b2.Spec.Tick);equal(sell.Average,(ref-2)*b2.Spec.Tick)
  assert(e2.Accounts[id2].Balance<e2.Accounts[id2].Base);e2:Audit()
 end)
'''+s[b:];p.write_text(s,encoding='utf-8')
