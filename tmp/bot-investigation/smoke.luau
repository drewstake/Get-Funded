local Engine=require('./modules/MarketEngine')
local Participants=require('./modules/Participants')
local Config=require('./modules/MarketConfig')
local e=Engine.new(Config,73521)
local p=Participants.new(e)
local start=os.clock()
for step=1,400 do p:Step()end
print('OK',e.Time,e.NextTrade,os.clock()-start,e:Audit())
