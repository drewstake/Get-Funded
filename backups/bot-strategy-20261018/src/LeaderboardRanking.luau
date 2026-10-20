-- Pure projection of the authoritative funded ledger. Never accepts client scores.

local Rules=require(game.ReplicatedStorage.MarketReign.ProgressionRules)
local Ranking={Limit=100}

function Ranking.Row(funded,uid,identity)

 local p=funded:Profile(uid)

 local row={UserId=tonumber(uid),Name=identity and identity.Name or p and p.PlayerName,

  DisplayName=identity and identity.DisplayName or p and p.DisplayName,Cents=0,Eligible=false,Tier="—",TierSize=0}

 if not row.UserId or row.UserId%1~=0 then return nil end

 if not p then return row end

 local profit=funded.Engine.Accounts[p.Account].Balance

 assert(profit==profit and math.abs(profit)<9e13,"Invalid account balance")

 row.Cents=math.round(profit*100)

 local trades=funded:_counts(p)

 row.Eligible=trades>0

 local rank=Rules.Rank(p.RankId)
 row.ProgressionRankId=rank and rank.Id;row.ProgressionVersion=p.ProgressionVersion
 row.Tier=rank and rank.Name or nil;row.TierSize=0

 return row

end

function Ranking.Sort(rows,limit)

 local result,seen={},{}

 for _,row in ipairs(rows) do

  if row and row.Eligible and not seen[row.UserId] then seen[row.UserId]=true;table.insert(result,table.clone(row)) end

 end

 table.sort(result,function(a,b) if a.Cents~=b.Cents then return a.Cents>b.Cents end return a.UserId<b.UserId end)

 while limit and #result>limit do table.remove(result) end

 for i,row in ipairs(result) do row.Rank=i end

 return result

end

function Ranking.Capture(funded)

 local rows={}

 for uid in pairs(funded.Engine.Profiles) do

  local row=Ranking.Row(funded,uid)

  -- Studio's synthetic negative user ids are allowed only by its separate store scope.

  if row then table.insert(rows,row) end

 end

 return Ranking.Sort(rows,Ranking.Limit)

end

function Ranking.Standing(own,rows,verified)

 own=table.clone(own);own.Rank=nil

 if not own.Eligible then own.Status="Close a trade to join";return own end

 own.Status="Outside top 100"

 if verified then

  for _,row in ipairs(rows) do

   if row.UserId==own.UserId and row.Cents==own.Cents then own.Rank=row.Rank;own.Status="#"..row.Rank;break end

  end

 end

 return own

end

return Ranking

