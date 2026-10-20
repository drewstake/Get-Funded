local fs=require('@lune/fs');local serde=require('@lune/serde')
local variants={baseline={require('./baseline/MarketEngine'),require('./baseline/MarketConfig')},candidate={require('./candidate/MarketEngine'),require('./candidate/MarketConfig')}}
local report={}
local function clone(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
for _,name in ipairs({'baseline','candidate'})do
 local E,C=table.unpack(variants[name]);local rows={};report[name]=rows
 local function measure(label,fn)
  local at=os.clock();local result=table.pack(fn());local ms=(os.clock()-at)*1000
  rows[label]=rows[label]or {};table.insert(rows[label],ms);return table.unpack(result,1,result.n)
 end
 for _,q in ipairs({8000,13000,50000})do for _=1,12 do
  local c=clone(C);c.BotPopulation=nil;c.Contracts.BX.Last=5230.25
  local e=E.new(c,15)
  for _,id in ipairs({'player','maker','buyer'})do local a=e:AddAccount(id,1000000000,1000000,.8,id=='player');a.LiquidityProvider=true end
  assert(e:Submit('player',{Contract='BX',Direction=1,Quantity=q,Type='Limit',Price=5230.25,TargetTicks=18}))
  measure(q..':EntryAndProtection',function()assert(e:Submit('maker',{Contract='BX',Direction=-1,Quantity=q,Type='Market'}))end)
  local n=e.NextTrade
  measure(q..':TargetFill',function()local ok,r=e:Submit('buyer',{Contract='BX',Direction=1,Quantity=q,Type='Market'});assert(ok and r.Filled==q)end)
  assert(e.NextTrade==n+1 and not e.Accounts.player.Positions.BX)
  local _,o=e:Submit('player',{Contract='BX',Direction=1,Quantity=q,Type='Limit',Price=5220})
  measure(q..':Amend',function()assert(e:AmendOrder('player',{Contract='BX',OrderId=o.Id,ExpectedQuantity=q,ExpectedPrice=5220,Price=5220.25}))end)
  measure(q..':Cancel',function()assert(e:Cancel('player',o.Id))end)
  measure(q..':Snapshot',function()e:Snapshot('player','BX','1m',false)end)
  e:Audit()
 end end
 for label,samples in pairs(rows)do
  table.sort(samples);local sum=0;for _,v in ipairs(samples)do sum+=v end
  rows[label]={Count=#samples,MeanMs=sum/#samples,P95Ms=samples[math.ceil(#samples*.95)],MaxMs=samples[#samples]}
 end
end
fs.writeFile('output/execution-integrity-20261015/latency.json',serde.encode('json',report))
print(serde.encode('json',report))
