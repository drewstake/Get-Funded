local E=require('./candidate/MarketEngine');local P=require('./candidate/Participants');local C=require('./candidate/MarketConfig')
local t=os.clock();local e=E.new(C,19381);local p=P.new(e);print('created',os.clock()-t,#p.Agents)
for i=1,240 do p:Step();if i%40==0 then print(i,os.clock()-t,e.NextTrade)end end
