-- A simulation step is atomic. Preserve every remaining step for a later frame,
-- but do not run a long catch-up batch before the client can receive an update.
local Scheduler={}
function Scheduler.Advance(backlog,config,advance,clock,started)
 clock=clock or os.clock;started=started or clock()
 local steps=0;local limited=false
 local budget=(config.SimulationFrameBudgetMs or 8)/1000
 while backlog>=config.StepSeconds and steps<config.MaxCatchupSteps do
  if steps>0 and clock()-started>=budget then limited=true;break end
  if advance()==false then break end
  backlog-=config.StepSeconds;steps+=1
 end
 return backlog,steps,limited
end
return Scheduler
