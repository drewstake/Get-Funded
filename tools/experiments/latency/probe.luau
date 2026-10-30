-- Runs only on an independently restored saved world. The caller owns transport.
local Probe={}
local function summary(values)
 table.sort(values);local sum=0;for _,v in ipairs(values)do sum+=v end
 return {Count=#values,MeanMs=sum/math.max(1,#values),P50Ms=values[math.max(1,math.ceil(#values*.5))],P95Ms=values[math.max(1,math.ceil(#values*.95))],P99Ms=values[math.max(1,math.ceil(#values*.99))],MaxMs=values[#values]}
end
Probe.Summary=summary
function Probe.Run(get,snapshot,options)
 options=options or {};local CP=get('WorldCheckpoint');local C=get('MarketConfig')
 local Policy=get('PlayerExecution');local Safety=get('MarketSafety')
 local e,p=CP.Restore(snapshot,C);local original=CP.Capture(e,p)
 local owner='player:42875739:single:13';assert(e.Accounts[owner])
 e:SetConnectedOwners({[owner]=true})
 local yield=options.Yield or function()end
 local report={Scope=options.Scope,StartStep=e.Step,Participants=#p.Agents,Reserves=#e.Books.BX.ReserveProviders,Steps=options.Steps or 2400,EmptyEpisodes={},QuoteGaps={},Scopes={}}
 local stepTimes,snapshotTimes,payloadBytes={}, {}, {};local frames={};local originalFunctions={};local stack={}
 local function wrap(object,name,label,custom)
  local fn=object[name];if type(fn)~='function'then return end
  local own=rawget(object,name);table.insert(originalFunctions,{object,name,own})
  if custom then object[name]=custom(fn);return end
  local row={Calls=0,Ms=0,SelfMs=0,MaxMs=0};report.Scopes[label or name]=row
  object[name]=function(...)
   local at=os.clock();local frame={Child=0};table.insert(stack,frame)
   local result=table.pack(fn(...));local ms=(os.clock()-at)*1000;table.remove(stack)
   if #stack>0 then stack[#stack].Child+=ms end
   row.Calls+=1;row.Ms+=ms;row.SelfMs+=ms-frame.Child;row.MaxMs=math.max(row.MaxMs,ms)
   return table.unpack(result,1,result.n)
  end
 end
 local agents={};local gaps={};local gapSamples={};local retirements={};local current;local cancelReasons={}
 for _,a in ipairs(p.Agents)do agents[a.Id]=a end
 wrap(e,'Cancel',nil,function(fn)return function(self,owner,id)
  local o=self.Orders[id]
  if o then
   cancelReasons[id]=o.Expires and o.Expires<=e.Time and 'Expired'
    or not Policy.Allows(e,e.Books[o.Contract],o.Price or e.Books[o.Contract].Reference,-o.Direction)and 'PriceRestriction'
    or self:_available(o,true)<=0 and 'InventoryOrRisk'
    or (current=='_maker'or current=='_reserve')and 'StrategyCancellation'or 'OtherCancellation'
  end
  local result=table.pack(fn(self,owner,id));cancelReasons[id]=nil;return table.unpack(result,1,result.n)
 end end)
 wrap(e,'_retire',nil,function(fn)return function(self,o,status)
  local a=agents[o.Owner]
  if a and (a.Kind=='Maker'or a.Kind=='Reserve')then
   for slot,id in pairs(a.Quotes or {})do if id==o.Id then
    local reason=status=='Filled'and 'Consumed'or status
    if status=='Cancelled'then reason=cancelReasons[o.Id]or status end
    retirements[reason]=(retirements[reason]or 0)+1
    gaps[a.Id..'/'..slot]={At=e.Time,Kind=a.Kind,Reason=reason,Slot=slot,Order=o.Id}
   end end
  end
  return fn(self,o,status)
 end end)
 for _,name in ipairs({'_maker','_reserve'})do wrap(p,name,nil,function(fn)return function(self,a)
  current=name;local result=table.pack(fn(self,a));current=nil
  for slot,id in pairs(a.Quotes or {})do
   local key=a.Id..'/'..slot;local gap=gaps[key]
   if gap and id~=gap.Order and e.Orders[id]then
    local label=gap.Kind..':'..gap.Reason;gapSamples[label]=gapSamples[label]or {};table.insert(gapSamples[label],(e.Time-gap.At)/C.SimulationSpeed*1000)
    gaps[key]=nil
   end
  end
  return table.unpack(result,1,result.n)
 end end)end
 local open={};local emptyCounts={Bids=0,Asks=0};local statuses={};local lastRetirements={}
 local function inspect(side,depth)
  local row={Step=e.Step,Time=e.Time,Side=side,Status=depth.Status[side],PhysicalLevels=#e.Books.BX[side],EligibleOrders=0,Blocked={},MakerCooldowns=0,ReserveCooldowns=0,InventoryLimited=0,RiskPaused=0}
  for _,level in ipairs(e.Books.BX[side])do for _,o in ipairs(level.Orders)do
   local n,why=e:_available(o,true);if n>0 and Policy.Allows(e,e.Books.BX,o.Price,-o.Direction)then row.EligibleOrders+=1
   else why=n>0 and 'PriceRestriction'or why;row.Blocked[why]=(row.Blocked[why]or 0)+1 end
  end end
  for _,a in ipairs(p.Agents)do if a.Kind=='Maker'or a.Kind=='Reserve'then
   local ac=e.Accounts[a.Id];local position=ac.Positions.BX;local sign=side=='Bids'and 1 or -1
   if ac.Locked or ac.Liquidating or a.Retiring or a.Retired then row.RiskPaused+=1 end
   if not e:Exposure(ac,'BX',sign,1)and not(position and position.Direction==-sign)then row.InventoryLimited+=1 end
   for slot,at in pairs(a.Kind=='Maker'and a.ReplenishAt or a.ReserveReplenishAt or {})do
    if slot:sub(1,#tostring(sign))==tostring(sign)and at>e.Time then
     local key=a.Kind=='Maker'and 'MakerCooldowns'or 'ReserveCooldowns';row[key]+=1
    end
   end
  end end
  row.RetirementsSincePreviousStep={};for k,n in pairs(retirements)do local delta=n-(lastRetirements[k]or 0);if delta>0 then row.RetirementsSincePreviousStep[k]=delta end end
  return row
 end
 local startTrade=e.NextTrade;local startOrder=e.NextOrder
 for i=1,report.Steps do
  local at=os.clock();p:Step();table.insert(stepTimes,(os.clock()-at)*1000)
  if i%7==0 then
   at=os.clock();local packet=e:Snapshot(owner,'BX','5m',false);table.insert(snapshotTimes,(os.clock()-at)*1000)
   if options.EncodeJSON then packet.History=nil;packet.Fills=nil;table.insert(payloadBytes,#options.EncodeJSON(packet))end
  end
  local depth=e:PublicDepth('BX')
  for _,side in ipairs({'Bids','Asks'})do
   local key=side..':'..depth.Status[side];statuses[key]=(statuses[key]or 0)+1
   if #depth[side]==0 then
    emptyCounts[side]+=1
    if not open[side]then open[side]=inspect(side,depth)end
   elseif open[side]then
    local row=open[side];row.DurationSimSeconds=e.Time-row.Time;row.IdealWallMs=row.DurationSimSeconds/C.SimulationSpeed*1000
    if #report.EmptyEpisodes<100 then table.insert(report.EmptyEpisodes,row)end;open[side]=nil
   end
  end
  lastRetirements=table.clone(retirements)
  if i%100==0 and options.Progress then options.Progress(i)end
  yield(i)
 end
 report.OpenEmptyEpisodes=open;report.EmptySteps=emptyCounts;report.DepthStatuses=statuses;report.Retirements=retirements
 for label,samples in pairs(gapSamples)do report.QuoteGaps[label]=summary(samples)end
 report.Step=summary(stepTimes);report.Snapshot=summary(snapshotTimes);report.PayloadBytes=summary(payloadBytes)
 report.NewTrades=e.NextTrade-startTrade;report.NewOrders=e.NextOrder-startOrder;report.Audit=e:Audit()
 -- Profile a separate continuation; scope instrumentation is excluded from Step timings.
 for _,name in ipairs({'Submit','_match','Cancel','AmendOrder','Summary','Exposure','OrderCapacity','_pruneBook','_cleanBook','_available','_rest','_unrest','_trade','AdvanceClock','ProcessStops','ProcessPlayerOrders','Snapshot'})do wrap(e,name)end
 for _,name in ipairs({'Step','_maker','_reserve','_trader','_scalper','_fit','_repairRisk','_observe','_publicInformation'})do wrap(p,name,'Bot.'..name)end
 for _,name in ipairs({'Capacity','ReserveLimit','Bounds','RetryExits'})do wrap(Safety,name,'Safety.'..name)end
 for _,name in ipairs({'Budget','Liquidity'})do wrap(Policy,name,'Execution.'..name)end
 for i=1,(options.ProfileSteps or 300)do p:Step();if i%7==0 then e:Snapshot(owner,'BX','5m',false)end;yield(i)end
 for i=#originalFunctions,1,-1 do local item=originalFunctions[i];item[1][item[2]]=item[3]end
 local captures,encodes={},{}
 for i=1,3 do
  local at=os.clock();local saved=CP.Capture(e,p);table.insert(captures,(os.clock()-at)*1000);yield(i)
  at=os.clock();local record=CP.EncodeWorld(e,p);table.insert(encodes,(os.clock()-at)*1000)
  report.RawBytes=record.RawBytes;report.EncodedBytes=#record.Payload+(record.Archive and #record.Archive.Payload or 0);yield(i)
 end
 report.Capture=summary(captures);report.EncodeWorld=summary(encodes)
 if CP.EncodingMetrics then report.EncodingStages=CP.EncodingMetrics(e)end
 report.FinalStep=e.Step
 return report
end
return Probe
