-- In-memory, keyed storage for persistence regressions. Never requests a Roblox service.
local Http=game:GetService("HttpService")
local Settings=require(script.Parent.WorldConfig)
local Fake={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
function Fake.new(clock)
 local s={Values={},Writes={},Now=clock or function()return 1000 end}
 function s:UpdateAsync(key,callback)
  if self.BeforeWrite then self.BeforeWrite(key)end
  if self.Fail then error("Injected storage outage")end
  local old=self.Values[key]
  if self.ReplayCallback then callback(clone(old))end
  local value=callback(clone(old))
  if value==nil then return nil end
  if self.BeforeCommit then self.BeforeCommit(key,value,old)end
  local bytes=math.ceil(#Http:JSONEncode(value)/1024)*1024
  local now=self.Now();local used=bytes
  for _,write in ipairs(self.Writes)do if write.Key==key and write.At>now-60 then used+=write.Bytes end end
  if self.EnforceBudget then assert(used<=4000000,"Injected per-key write throttle")end
  table.insert(self.Writes,{Key=key,At=now,Bytes=bytes})
  self.Values[key]=clone(value)
  self.PrimaryKey=self.PrimaryKey or key
  if key==self.PrimaryKey then self.Value=self.Values[key]end
  -- The existing transaction tests inject a lost FINAL commit response, not a
  -- staging reservation. Publication is the only point that changes durable funds.
  local published=key==Settings.WorldKey and value.SaveSequence and value.SaveSequence>(old and old.SaveSequence or 0)
  if self.AfterCommit then self.AfterCommit(key,value,old)end
  if self.LostReply and published then error("Injected lost commit confirmation")end
  return clone(value)
 end
 function s:GetAsync(key,options)
  if self.Fail then error("Injected storage outage")end
  self.LastReadOptions=options
  self.ReadUncached=options and options.UseCache==false or false
  return clone(self.Values[key])
 end
 return s
end
return Fake
