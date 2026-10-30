-- Explicit historical multi-market fixtures. Production remains BX-only; tests
-- retain coverage of cross-market limits, protection and different tick sizes.
local Production=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Fixtures={}
local function copy(v)
 if type(v)~='table'then return v end
 local out={}for k,x in pairs(v)do out[k]=copy(x)end return out
end
function Fixtures.BXVersion2()
 local c=copy(Production);c.BotPopulation.Version=2
 c.BotPopulation.Counts={Maker=60,Liquidity=72,Momentum=36,Value=60,Reversion=36,Protective=24,Scalper=72,Whale=12,Reserve=18}
 c.ParticipantsPerInstrument=228;c.MakersPerInstrument=60;c.ScalpersPerInstrument=72;c.WhalesPerInstrument=12;c.Reserve.Count=18
 return c
end
function Fixtures.ThreeMarkets()
 local c=Fixtures.BXVersion2();c.ContractOrder={'BX','BT','BG'}
 for _,key in ipairs({'BT','BG'})do
  c.Contracts[key]=copy(c.LegacyContracts[key]);c.Contracts[key].CloseOnly=nil
 end
 return c
end
return Fixtures
