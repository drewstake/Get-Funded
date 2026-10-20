local fs=require('@lune/fs');local serde=require('@lune/serde')
local path='output/order-driven-market-20261019/tests.json'
local previous=serde.decode('json',fs.readFile(path));fs.writeFile('output/order-driven-market-20261019/tests-before-legacy-fixture-updates.json',serde.encode('json',previous,true))
for _,name in ipairs({'OrderFlowMarketTests','SharedDepthTests','MarketTests','ProtectiveOrdersTests'})do
 local rows=require('./candidate/'..name).Run();previous.Suites[name]=rows.Results or rows;print('Completed',name)
end
previous.Total=0;previous.Failures=0
for name,suite in pairs(previous.Suites)do for _,r in ipairs(suite)do previous.Total+=1;if not r.Passed then previous.Failures+=1;print(name,r.Name,r.Detail)end end end
fs.writeFile(path,serde.encode('json',previous,true));print('Total',previous.Total,'Failures',previous.Failures);assert(previous.Failures==0)
