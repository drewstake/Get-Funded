local fs=require('@lune/fs');local serde=require('@lune/serde')
local out={Total=0,Failures=0,Suites={}}
for _,name in ipairs({'BotPublicInformationTests','SharedDepthTests','DepthRealismTests','BotFairnessTests','BotSignalsTests','ScalperTests','BotPopulationTests','BotRefreshTests','BotStatsTests','BotExitRetryTests','MakerLiquidityTests','ExecutionIntegrityTests','MarketTests','WorldTests','ProtectiveOrdersTests'})do
 local ok,result=pcall(function()return require('./candidate/'..name).Run()end)
 if not ok then result={{Name='Suite',Passed=false,Detail=tostring(result)}}end
 result=result.Results or result
 out.Suites[name]=result
 for _,row in ipairs(result)do out.Total+=1;if not row.Passed then out.Failures+=1;print(name,row.Name,row.Detail)end end
 print('Completed',name)
end
fs.writeFile('output/public-bot-information-20261019/tests.json',serde.encode('json',out,true))
print('Total',out.Total,'Failures',out.Failures);assert(out.Failures==0)
