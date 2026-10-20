local fs=require("@lune/fs")
local s=require("@lune/serde")
local t=require("./proposed/BotExitRetryTests")
local rows=t.Run()
local failures=0
for _,r in ipairs(rows)do print(r.Name,r.Passed,r.Detail);if not r.Passed then failures+=1 end end
local result={Results=rows,Failures=failures,Baseline=require("./baseline/BotExitRetryTests").Benchmark(256),Proposed=t.Benchmark(256)}
fs.writeFile("output/bot-exit-performance-20261015/offline-focused.json",s.encode("json",result))
print(s.encode("json",result))
assert(failures==0)
