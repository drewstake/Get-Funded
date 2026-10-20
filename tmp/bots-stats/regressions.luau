local fs=require('@lune/fs');local serde=require('@lune/serde')
local names={'BotStatsTests','BotRefreshTests','ExecutionIntegrityTests','BotExitRetryTests','BotPopulationTests','ProtectiveOrdersTests','ResetLiquidationTests','MarketTests','ExecutionChoiceTests','SharedDepthTests','TradeLimitsTests','ClosedTradePnlTests','TradePreferencesTests','DepthRealismTests','ScalperTests','MakerLiquidityTests','WorldTests','CapacityTests','SingleAccountTests','AccountUpgradeTests','OwnerGiveTests','OwnerResetTests','RankBadgeTests','SecurityTests','TradeAmendmentTests','ProtectionScaleTests','AmountInputTests'}
local report={Total=0,Failures=0,Suites={}}
table.insert(names,1,'RequestJournalTests')
for _,name in ipairs(names)do
 local ok,result=pcall(function()local module=require('./candidate/'..name);return type(module)=='function'and module()or module.Run()end)
 local rows=ok and(result.Results or result.Cases and {{Name='Assertions',Passed=result.Passed,Count=result.Cases}}or result)or{{Name='Suite',Passed=false,Detail=tostring(result)}}
 report.Suites[name]=rows
 for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1;print(name,row.Name,row.Detail)end end
 print('Finished',name)
end
fs.writeFile('output/bots-stats-20261015/regressions.json',serde.encode('json',report))
print('TOTAL',report.Total,'FAILURES',report.Failures)
