-- Shared wire-state rules. Account responses never claim that depth was refreshed.
local Packet={}
local metadata={'Milestones','Ranks','Awards','Titles','Next','RankNext','ProtectionPreferences'}
function Packet.Portfolio(value,previousKey,key,full)
 if full or previousKey~=key then return value,false end
 local delta=table.clone(value)
 for _,field in ipairs(metadata)do delta[field]=nil end
 return delta,true
end
function Packet.ApplyPortfolio(previous,value,delta)
 if not delta then return value end
 if not previous or previous.Active~=value.Active or previous.Revision~=value.Revision then return nil end
 local result=table.clone(value)
 for _,field in ipairs(metadata)do result[field]=previous[field]end
 return result
end
function Packet.ApplyAccount(session,packet)
 session.Base=packet.Base;session.Positions=packet.Positions
 session.Orders=packet.Orders or session.Orders;session.History=packet.History or session.History;session.Fills=packet.Fills or session.Fills
 session.SummaryData=packet.Summary;session.Capacity=packet.Capacity;session.Limit=packet.Limit;session.Triggers=packet.Triggers or {}
end
function Packet.AcceptAccount(session,packet)
 return session.Ready and packet.AccountToken==session.AccountToken and packet.RequestSession==session.RequestSession
end
return Packet
