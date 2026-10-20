local E=require('./candidate/MarketEngine');local P=require('./candidate/Participants');local C=require('./candidate/MarketConfig')
local out={}
for _,spec in ipairs({{E,{'Summary','Exposure','PublicDepth','ProcessStops','_pruneBook','_syncReductions','_match','_trade','AdvanceClock'}},{P,{'_maker','_reserve','_trader','_scalper','_observe','_repairRisk'}}})do
 for _,name in ipairs(spec[2])do local original=spec[1][name];out[name]={Seconds=0,Calls=0};spec[1][name]=function(self,...)
 local t=os.clock();local result=table.pack(original(self,...));local row=out[name];row.Seconds+=os.clock()-t;row.Calls+=1;return table.unpack(result,1,result.n)end end
end
local e=E.new(C,19381);local p=P.new(e)
for _,row in pairs(out)do row.Seconds=0;row.Calls=0 end
for i=1,240 do p:Step()end
for name,row in pairs(out)do print(name,row.Seconds,row.Calls)end
