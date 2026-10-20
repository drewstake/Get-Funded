local fs=require('@lune/fs');local serde=require('@lune/serde');local process=require('@lune/process')
local names={'BotSignalsTests','ScalperTests','BotPopulationTests','BotRefreshTests','WorldTests','BotExitRetryTests','MarketTests','ExecutionIntegrityTests','ProtectiveOrdersTests'}
local report={Total=0,Failures=0,Suites={}}
for _,name in ipairs(names)do
 local ok,result=pcall(function()return require('./candidate/'..name).Run()end)
 local rows=ok and(result.Results or result)or{{Name='Suite',Passed=false,Detail=tostring(result)}}
 report.Suites[name]=rows
 for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1;print(name,row.Name,row.Detail)end end
 print('Finished',name)
end
fs.writeFile('output/bot-strategy-20261018/tests.json',serde.encode('json',report,true))
print('TOTAL',report.Total,'FAILURES',report.Failures)
assert(report.Failures==0,'Regression failures')
