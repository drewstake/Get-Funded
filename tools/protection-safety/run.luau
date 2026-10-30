local fs=require('@lune/fs');local serde=require('@lune/serde');local process=require('@lune/process');local luau=require('@lune/luau')
local Report=require('./report')
local names=process.args
local all=names[1]=='--all'
if all then names={};for _,file in ipairs(fs.readDir('output/c1-protection-fix-20261026/original'))do if file:match('Tests%.luau$')then table.insert(names,file:sub(1,-6))end end;table.sort(names);assert(#names>0,'No test suites discovered')end
if #names==0 then names={'ProtectionSafetyTests','ProtectiveOrdersTests','ExecutionIntegrityTests','ExecutionChoiceTests','WorldTests','RequestJournalTests','OrderFlowMarketTests','AmountInputTests'}end
local report={Total=0,Failures=0,Suites={},Compiled=0}
for _,file in ipairs(fs.readDir('output/c1-protection-fix-20261026/original'))do if file:match('%.luau$')then luau.compile(fs.readFile('output/c1-protection-fix-20261026/original/'..file));report.Compiled+=1 end end
local seen={}
for _,name in ipairs(names)do
 assert(not seen[name]and name:match('^[%w_]+Tests$'),'Duplicate or invalid suite name');seen[name]=true
 local ok,result=pcall(function()local m=require('./candidate/'..name);return Report.Rows(type(m)=='function'and m()or m.Run())end)
 local rows
 if not ok then rows={{Name='Suite',Passed=false,Detail=tostring(result)}}
 else rows=result end
 report.Suites[name]=rows
 for _,row in ipairs(rows)do report.Total+=1;if row.Passed==false then report.Failures+=1;print('FAIL',name,row.Name,row.Detail)end end
 print('Finished',name,#rows)
end
fs.writeFile('output/c1-protection-fix-20261026/'..(all and 'all-results'or 'results')..'.json',serde.encode('json',report,true));print('TOTAL',report.Total,'FAILURES',report.Failures,'COMPILED',report.Compiled)
if report.Failures>0 then process.exit(1)end
