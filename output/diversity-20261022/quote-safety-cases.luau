 for _,side in ipairs({1,-1})do for _,passive in ipairs({false,true})do
  test('Missing required quote never falls through to the other side: '..tostring(side)..'/'..tostring(passive),function()
   local e,p,a,b,s=fixture(side,passive)
   quote(e,b,passive and -side or side)
   local orders=e.NextOrder;local volume=e.TotalVolume;local last=b.Last
   advance(e,p,a,10)
   assert(e.NextOrder==orders and e.TotalVolume==volume and b.Last==last and not s.ChildId and not next(e.Accounts[a.Id].OpenOrders))
   e:Audit()
  end)
 end end
