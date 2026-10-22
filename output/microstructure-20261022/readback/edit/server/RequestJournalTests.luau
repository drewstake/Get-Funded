local Journal=require(script.Parent.RequestJournal)
local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local CP=require(script.Parent.WorldCheckpoint)
local P=require(script.Parent.Participants)
local Queue=require(script.Parent.RequestQueue)
local Tests={}
function Tests.Run(yieldBetween)
 local rows={};local function test(name,fn)if yieldBetween then yieldBetween()end;local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Retry returns the original result and cannot create another order or fill',function()
  local e=E.new(C,15);e:AddAccount('p',1000000,1000,.8,true);e:AddAccount('maker',1000000,1000,.8,false)
  local price=C.Contracts.BX.Last
  assert(e:Submit('maker',{Contract='BX',Direction=-1,Quantity=10,Type='Limit',Price=price}))
  local session=Journal.Open(e,'uid')
  local function process(id)
   local accepted,cached=Journal.Begin(e,'uid',session,id);if not accepted then return cached end
   local ok,result=e:Submit('p',{Contract='BX',Direction=1,Quantity=2,Type='Market'})
   local reply={Ok=ok,Result=result};Journal.Finish(e,'uid',session,id,reply);return reply
  end
  local first=process(1);local count=e.NextTrade;local order=e.NextOrder
  assert(first.Ok and first.Result.Filled==2)
  for _=1,100 do assert(process(1).Result.Id==first.Result.Id)end
  assert(e.NextTrade==count and e.NextOrder==order and e.Accounts.p.Positions.BX.Quantity==2);e:Audit()
 end)
 test('Reply eviction, changed payload and reconnect cannot resurrect a consumed request',function()
  local e={};local session=Journal.Open(e,'uid')
  for id=1,1000 do assert(Journal.Begin(e,'uid',session,id));Journal.Finish(e,'uid',session,id,{Id=id})end
  local accepted,cached,reason=Journal.Begin(e,'uid',session,1)
  assert(not accepted and not cached and reason:find('already processed',1,true))
  assert(#e.RequestJournal.uid.Order==Journal.MaxReplies)
  local nextSession=Journal.Open(e,'uid');assert(nextSession==session+1)
  assert(not Journal.Begin(e,'uid',session,1001));assert(Journal.Begin(e,'uid',nextSession,1))
 end)
 test('Interleaved owners retain their own request order; consumed failures never execute twice',function()
  local e={};local a=Journal.Open(e,'a');local b=Journal.Open(e,'b');local sequence={}
  for _,row in ipairs({{'a',a,1},{'b',b,1},{'a',a,2},{'a',a,2},{'b',b,2}})do
   if Journal.Begin(e,row[1],row[2],row[3])then table.insert(sequence,row[1]..row[3])end
  end
  assert(table.concat(sequence,',')=='a1,b1,a2,b2')
  assert(not Journal.Begin(e,'a',a,1)and not Journal.Begin(e,'a',a,2))
 end)
 test('Checkpoint persists request sessions, high-water marks and acknowledgements atomically',function()
  local c=table.clone(C);c.BotPopulation=nil;local e=E.new(c,15)
  local session=Journal.Open(e,'uid');assert(Journal.Begin(e,'uid',session,7))
  Journal.Finish(e,'uid',session,7,{Ok=true,Result={Id=23,Filled=5}})
  local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(15),Agents={}},P)
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),c)
  local accepted,cached=Journal.Begin(restored,'uid',session,7)
  assert(not accepted and cached.Ok and cached.Result.Id==23)
  assert(not Journal.Begin(restored,'uid',session,6));assert(Journal.Open(restored,'uid')==session+1)
 end)
 test('256 simultaneous accepted requests retain FIFO across bounded steps and new arrivals',function()
  local queue={};for i=1,256 do table.insert(queue,i)end
  local consumed={};local batches=0
  while #queue>0 do
   local batch;batch,queue=Queue.Take(queue);assert(#batch<=16);batches+=1
   for _,value in ipairs(batch)do table.insert(consumed,value)end
   if batches==1 then table.insert(queue,257)end
  end
  assert(#consumed==257 and batches==17)
  for i,value in ipairs(consumed)do assert(i==value,'Accepted requests reordered or dropped')end
 end)
 return rows
end
return Tests
