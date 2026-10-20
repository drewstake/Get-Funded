local E=require('./candidate/MarketEngine');local P=require('./candidate/Participants');local C=require('./candidate/MarketConfig')
local e=E.new(C,9);local p=setmetatable({Engine=e},P)
p._step=function()error('Injected participant failure')end
assert(not pcall(p.Step,p));assert(e.ProcessingParticipants==nil)
print('Failed participant steps clear batching scope before external requests')
