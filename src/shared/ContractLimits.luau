-- Shared presentation/server policy. Only the server's closed balance authorizes exposure.
local Config=require(script.Parent.ProgressionConfig)
local Limits={}
function Limits.ForBalance(balance)
 -- Use the same cent precision as the balance readout, avoiding floating-point
 -- settlement noise just below an exact $1,000 boundary.
 local cents=math.round(balance*100)
 return math.max(Config.MinimumContracts,math.floor(cents/(Config.BalancePerContract*100)))
end
return Limits
