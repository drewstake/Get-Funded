-- Benchmarks detached restored worlds, including retained legacy accounts and pending obligations.
local Benchmark={}
local function pct(list,q)table.sort(list);return list[math.max(1,math.ceil(#list*q))]or 0 end
function Benchmark.Run(e,p,CP,seconds,yield)
 local steps=math.floor(seconds/e.Config.StepSeconds);local times,saves={},{}
 local compute,matching,calls,raw,encoded=0,0,0,0,0
 local match=e._match
 e._match=function(self,...)
  local start=os.clock();local ok,r=match(self,...);matching+=os.clock()-start;calls+=1;return ok,r
 end
 local trades,volume=e.NextTrade,e.TotalVolume
 for i=1,steps do
  local start=os.clock();p:Step();local elapsed=os.clock()-start;compute+=elapsed;table.insert(times,elapsed)
  if i%1080==0 then
   local startSave=os.clock();local record=CP.Encode(CP.Capture(e,p));table.insert(saves,os.clock()-startSave)
   raw=math.max(raw,record.RawBytes);encoded=math.max(encoded,#record.Payload+4096);e:Audit()
  end
  if i%100==0 then yield()end
 end
 local saveTime=0;for _,v in ipairs(saves)do saveTime+=v end
 return {Seconds=seconds,Speed=e.Config.SimulationSpeed,Accounts=#e.AccountOrder,Agents=#p.Agents,
  StepComputeSeconds=compute,StepP95Ms=pct(times,.95)*1000,StepP99Ms=pct(times,.99)*1000,
  MatchingSeconds=matching,MatchingCalls=calls,CheckpointSeconds=saveTime,CheckpointP95Ms=pct(saves,.95)*1000,
  MaxRawBytes=raw,MaxEncodedWithHeadroom=encoded,ComputeFractionAt18x=(compute+saveTime)/(seconds/18),
  Trades=e.NextTrade-trades,Volume=e.TotalVolume-volume,Audit=e:Audit(),
  Scope='Roblox Studio Edit, detached copies of one saved Live snapshot; includes retained legacy bots and saved player accounts. No UI/network/broadcast/load from newly connected players. No writes to any DataStore. Simulation yields excluded from compute time. Matching is a subset of step time.'}
end
return Benchmark
