local fs=require('@lune/fs');local serde=require('@lune/serde');local H=require('./environment').game:GetService('HttpService')
local saved=H:JSONDecode(fs.readFile('backups/legacy-retirement-20261018/private-live-checkpoint.json'))
local OldCP=require('./baseline/WorldCheckpoint');local NewCP=require('./candidate/WorldCheckpoint')
local old=require('./baseline/MarketConfig');local new=require('./candidate/MarketConfig')
local snapshot=OldCP.Decode(saved.Record.Checkpoint);local result={Warmup=200,Steps=2000,Rounds=3,Baseline={},Candidate={}}
for round=1,result.Rounds do
 for _,name in ipairs(round%2==1 and {'Baseline','Candidate'}or {'Candidate','Baseline'})do
  local cp,c=name=='Baseline'and OldCP or NewCP,name=='Baseline'and old or new
  local e,p=cp.Restore(snapshot,c)
  for _=1,result.Warmup do p:Step()end
  local costs={};local time=os.clock()
  for _=1,result.Steps do local start=os.clock();p:Step();table.insert(costs,(os.clock()-start)*1000)end
  local ms=(os.clock()-time)*1000;table.sort(costs);e:Audit()
  local row={MeanMs=ms/result.Steps,P95Ms=costs[math.ceil(#costs*.95)],MaxMs=costs[#costs],Agents=#p.Agents,Books=#e.Config.ContractOrder,Accounts=#e.AccountOrder}
  table.insert(result[name],row);print(round,name,row.MeanMs)
 end
end
local function median(rows)local v={}for _,row in ipairs(rows)do table.insert(v,row.MeanMs)end table.sort(v)return v[2]end
result.BaselineMedianMs=median(result.Baseline);result.CandidateMedianMs=median(result.Candidate)
result.StepTimeReductionPercent=(1-result.CandidateMedianMs/result.BaselineMedianMs)*100
fs.writeFile('output/legacy-retirement-20261018/benchmark.json',serde.encode('json',result,true));print(result)
