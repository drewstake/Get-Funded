-- Shared definitions and pure presentation. Only FundedAccounts awards progression.
local Config=require(script.Parent.ProgressionConfig)
local Rules={}
function Rules.Rank(id)
 for index,r in ipairs(Config.Ranks) do if r.Id==id then return r,index end end
 return nil
end
function Rules.Metric(m,net,trades,wins)
 return math.max(0,m.Kind=="Trades" and trades or m.Kind=="Wins" and wins or net)
end
function Rules.Qualifies(r,net,trades,wins)
 return trades>=r.Trades and wins>=r.Wins and (r.Profit==0 or net+1e-6>=r.Profit)
end
function Rules.Obsolete(title)
 return title:match("^Legacy .*Trader$")~=nil or title:match("^%d+K Trader$")~=nil or title=="Legacy Top Tier Complete"
end
function Rules.Normalize(p,at)
 if p.ProgressionVersion==Config.ProgressionVersion then return false end
 p.LegacyProgression=p.LegacyProgression or {Titles=table.clone(p.Titles or {}),Rank=p.Rank}
 p.Awards=p.Awards or {};p.AlumniTitles=p.AlumniTitles or {}
 local known={};for _,m in ipairs(Config.Milestones)do known[m.Title]=m; if m.OldTitle then known[m.OldTitle]=m end end
 local seen={};for _,title in ipairs(p.AlumniTitles)do seen[title]=true end
 for _,title in ipairs(p.Titles or {})do
  local m=known[title]
  if m then p.Awards[m.Id]=p.Awards[m.Id] or {At=at,Title=title,Preserved=true}
  else
   local display=Rules.Obsolete(title) and "Founding Trader" or title
   if not seen[display]then table.insert(p.AlumniTitles,display);seen[display]=true end
  end
 end
 p.ProgressionVersion=Config.ProgressionVersion
 return true
end
function Rules.Titles(p)
 local titles,seen={},{};local current
 for _,m in ipairs(Config.Milestones)do if p.Awards[m.Id]then
  if not seen[m.Title]then table.insert(titles,m.Title);seen[m.Title]=true end;current=m
 end end
 for _,title in ipairs(p.AlumniTitles or {})do if not seen[title]then table.insert(titles,title);seen[title]=true end end
 return titles,current
end
return Rules
