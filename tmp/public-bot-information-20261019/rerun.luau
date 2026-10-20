local fs=require('@lune/fs');local serde=require('@lune/serde')
local path='output/public-bot-information-20261019/tests.json'
local previous=serde.decode('json',fs.readFile(path))
fs.writeFile('output/public-bot-information-20261019/tests-before-version-fixture-fix.json',serde.encode('json',previous,true))
local rows=require('./candidate/BotRefreshTests').Run()
previous.Suites.BotRefreshTests=rows.Results or rows
previous.Total=0;previous.Failures=0
for name,suite in pairs(previous.Suites)do for _,r in ipairs(suite)do
 previous.Total+=1;if not r.Passed then previous.Failures+=1;print(name,r.Name,r.Detail)end
end end
fs.writeFile(path,serde.encode('json',previous,true))
print('Total',previous.Total,'Failures',previous.Failures);assert(previous.Failures==0)
