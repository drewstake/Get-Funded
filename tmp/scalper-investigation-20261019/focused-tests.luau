local fs=require('@lune/fs');local serde=require('@lune/serde')
local out={Total=0,Failures=0,Suites={}}
for _,name in ipairs({'ScalperTests','BotSignalsTests','BotRefreshTests'})do
 local result=require('./modules/'..name).Run();out.Suites[name]=result
 for _,row in ipairs(result)do out.Total+=1;if not row.Passed then out.Failures+=1;print(name,row.Name,row.Detail)end end
end
fs.writeFile('output/scalper-investigation-20261019/focused-tests.json',serde.encode('json',out,true))
print('Total',out.Total,'Failures',out.Failures)
assert(out.Failures==0)
