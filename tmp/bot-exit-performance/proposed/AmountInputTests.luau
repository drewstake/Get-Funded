local Parse=require("./NumberInput").Parse
local Protection=require("./TradeProtection")
local C=require("./MarketConfig")
local Progression=require("./ProgressionConfig")
local E=require("./MarketEngine")
local F=require("./FundedAccounts")
local L=require("./TestLiquidity")
local Tests={}
function Tests.Run()
 local rows={}
 local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("Plain, currency and decimal shorthand parse without losing magnitude",function()
  for text,expected in pairs({["145"]=145,["145000"]=145000,["145k"]=145000,["145m"]=145000000,
   ["145.4k"]=145400,["145.4M"]=145400000,["145K"]=145000,["  $145,000.25  "]=145000.25,
   ["$145.4 K"]=145400,[".5m"]=500000,["0.001k"]=1,["1b"]=1e9,[".001T"]=1e9,
   ["1,234.56k"]=1234560,["0"]=0,["-1k"]=-1000,["+2k"]=2000})do
   assert(Parse(text)==expected,text.." parsed incorrectly")
  end
 end)
 test("Malformed, ambiguous and nonfinite numeric text is rejected",function()
  for _,text in ipairs({""," ","$",".","k","145kk","145km","145q","145.4.5k","1e6","nan","inf",
   "1$45","1,45k","1,,000","1234,000","1 45k","145k extra",string.rep("9",400).."m"})do
   assert(Parse(text)==nil,"Accepted "..text)
  end
  assert(Parse(145)==nil and Parse({})==nil)
 end)
 test("Large preferences save without quantity-dependent clamping",function()
  local e=E.new(C,901);local f=F.new(e,Progression,C);f:Join("amount-input")
  for _,text in ipairs({"145000","145k","145m","145.4k","1b"})do
   local n=Parse(text);local prefs={StopOn=true,TargetOn=true,StopDollars=n,TargetDollars=n}
   assert(f:SetProtectionPreferences("amount-input",prefs))
   assert(Protection.SamePreferences(prefs,f:View("amount-input").ProtectionPreferences))
  end
 end)
 for _,key in ipairs(C.ContractOrder)do for _,side in ipairs({1,-1})do
  test(key.." "..side..": large dollar stops reach filled positions",function()
   local spec=C.Contracts[key]
   for _,text in ipairs({"145000","145k","145m","145.4k","1b"})do
    local e=E.new(C,902);local a=e:AddAccount("amount-input",1e9,1000000,.9,true)
    local n=Parse(text);local resolved=assert(Protection.Resolve(spec,1,n,spec.Last,side,"Stop"))
    local ok,result=L.Submit(e,a.Id,{Contract=key,Direction=side,Quantity=1,Type="Market",StopDollars=n})
    assert(ok,tostring(result));local p=assert(a.Positions[key]);assert(p.Stop==resolved.Price)
    assert(math.abs((p.Entry-p.Stop)*side*spec.Multiplier-n)<=spec.Tick*spec.Multiplier/2+.001)
    e:Audit()
   end
  end)
  test(key.." "..side..": far targets and raw ticks are accepted without the old cap",function()
   local e=E.new(C,903);local a=e:AddAccount("amount-input",1e9,1000000,.9,true)
   local price=C.Contracts[key].Last-side*10*C.Contracts[key].Tick
   local ok,result=e:Submit(a.Id,{Contract=key,Direction=side,Quantity=1,Type="Limit",Price=price,TargetDollars=145e6})
   assert(ok,tostring(result));assert(e.Orders[result.Id].TargetTicks==Protection.Resolve(C.Contracts[key],1,145e6).Ticks)
   assert(e:Cancel(a.Id,result.Id))
   ok,result=e:Submit(a.Id,{Contract=key,Direction=side,Quantity=1,Type="Limit",Price=price,StopTicks=10001})
   assert(ok,tostring(result));e:Audit()
  end)
 end end
 test("Protection amount and raw tick bounds reject invalid requests atomically",function()
  local e=E.new(C,904);local a=e:AddAccount("amount-input",1e9,1000000,.9,true)
  for _,value in ipairs({0,-1,.001,1e9+.01,math.huge,0/0,"145k"})do
   assert(not Protection.Resolve(C.Contracts.BX,1,value))
   assert(not e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market",StopDollars=value}))
  end
  for _,value in ipairs({0,-1,1.5,math.huge,0/0,Protection.MaximumTicks(C.Contracts.BX,1)+1})do
   assert(not e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market",StopTicks=value}))
  end
  assert(not next(a.Positions)and not next(a.OpenOrders));e:Audit()
 end)
 return rows
end
return Tests
