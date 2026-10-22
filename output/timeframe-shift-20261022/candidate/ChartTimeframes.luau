-- Visible chart tiers use existing stored series. Exchange time and candle history stay intact.
-- Keys are the server/checkpoint series IDs; labels are the player-facing chart tiers.
local T={
 Default="5m",
 Order=table.freeze({"5m","15m","1h","1D"}),
 Labels=table.freeze({["5m"]="1m",["15m"]="5m",["1h"]="15m",["1D"]="1h"}),
 Tooltips=table.freeze({["5m"]="1 minute",["15m"]="5 minutes",["1h"]="15 minutes",["1D"]="1 hour"}),
}
return table.freeze(T)
