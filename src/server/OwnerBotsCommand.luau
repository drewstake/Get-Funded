-- Server-only owner policy; enqueue here and consume only at the scheduler boundary.
local Owner=require(script.Parent.OwnerResetCommand)
local Command={} Command.__index=Command
function Command.Parse(text)
 if type(text)~="string"or #text>80 then return nil end
 local action=text:lower():match("^%s*/bots%s+(%a+)%s*$")
 return (action=="refresh"or action=="stats")and action or nil
end
function Command.new(options)
 return setmetatable({Options=options,Busy=false,LastAt=setmetatable({},{__mode="k"})},Command)
end
function Command:Handle(player,text)
 local o=self.Options;local now=(o.Now or os.clock)()
 if now-(self.LastAt[player]or -math.huge)<2 then return end;self.LastAt[player]=now
 if not Owner.IsOwner(player.UserId,o.CreatorType,o.CreatorId,o.GroupLookup)then
  o.Notify(player,"Only the experience owner can use /bots commands.");return
 end
 local action=Command.Parse(text)
 if not action then o.Notify(player,"Usage: /bots refresh or /bots stats");return end
 if action=="stats"then
  if not o.StatsReady or not o.StatsReady()then o.Notify(player,"Bot stats are unavailable while the exchange is loading or saving. Try again shortly.");return end
  local ok,err=pcall(o.Stats,player)
  if not ok then warn("[Get Funded!] Bot stats: "..tostring(err));o.Notify(player,"Bot stats could not be prepared. Try again shortly.")end
  return
 end
 if self.Busy then o.Notify(player,"A bot refresh is already pending or saving.");return end
 if not o.Ready()then o.Notify(player,"The saved exchange is busy or unavailable. Try /bots refresh shortly.");return end
 self.Busy=true;self.Pending={Player=player,Actor=player.UserId,Sequence=o.NextSequence()}
end
function Command:AtBoundary()
 local item=self.Pending;local o=self.Options
 if not item or not o.Ready()then return false end
 self.Pending=nil
 -- Spawn starts the transaction synchronously, then yields only for the fenced store write.
 local spawn=o.Spawn or task.spawn
 spawn(function()
  local ok,saved,result=pcall(o.Refresh,item.Sequence,item.Actor)
  self.Busy=false
  if ok and saved then
   o.Notify(item.Player,string.format("Refreshed %d bots. Total capital adjustment: %s$%.2f. Saved.",
    result.Count,result.Amount<0 and "-"or "+",math.abs(result.Amount)))
  else
   o.Notify(item.Player,"Bot refresh was not confirmed. Check saved exchange status before retrying.")
   warn("[Get Funded!] Bot refresh: "..tostring(ok and result or saved))
  end
 end)
 return true
end
return Command
