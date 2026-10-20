local fs=require('@lune/fs');local serde=require('@lune/serde');local process=require('@lune/process')
local suites=#process.args>0 and process.args or {'BotPopulationTests','ProtectiveOrdersTests','ResetLiquidationTests','MarketTests','ExecutionChoiceTests','SharedDepthTests','TradeLimitsTests','ClosedTradePnlTests','TradePreferencesTests','DepthRealismTests','ScalperTests','MakerLiquidityTests','WorldTests'}
local results={};local failures=0
for _,name in ipairs(suites)do
 local ok,rows=pcall(function()return require('./proposed/'..name).Run()end)
 if not ok then rows={{Name='Suite load/run',Passed=false,Detail=tostring(rows)}}end
 rows=rows.Results or rows;results[name]=rows
 for _,row in ipairs(rows)do if not row.Passed then failures+=1;print('FAIL',name,row.Name,row.Detail)end end
 print('SUITE',name,#rows)
end
fs.writeFile('output/bot-population-20261014/tests.json',serde.encode('json',results,true))
print('FAILURES',failures)
if failures>0 then error('Test failures: '..failures)end
