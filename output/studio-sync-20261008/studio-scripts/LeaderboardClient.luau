-- Read-only transport with one request in flight, late-response rejection and visible-only refresh.
local Client={} Client.__index=Client
function Client.new(preview,data)
 local self=setmetatable({Preview=preview,Data=data,Tab="Global",Cache={},CacheAt={},Visible=false,Alive=true,Serial=0,
  Changed=Instance.new("BindableEvent"),NextRefresh=0},Client)
 if not preview then
  self.ResetConnection=script.Parent:GetAttributeChangedSignal("LeaderboardRevision"):Connect(function()
   self.Serial+=1;self.Busy=false;self.Cache={};self.CacheAt={};self.NextRefresh=0
   self.Data={Tab=self.Tab,State="Loading",Rows={}};self.Changed:Fire();self:Fetch(true)
  end)
 end
 return self
end
function Client.Stale(packet)
 local result=table.clone(packet);result.State="Stale"
 if result.Your then
  result.Your=table.clone(result.Your);result.Your.Rank=nil
  result.Your.Status=result.Your.Eligible and "Outside top 100" or "Close a trade to join"
 end
 result.Rows={}
 for _,row in ipairs(packet.Rows or {})do local r=table.clone(row);r.Rank=nil;table.insert(result.Rows,r)end
 return result
end
function Client:Cached(tab)
 local data=self.Cache[tab]
 if not data then return nil end
 if os.clock()-(self.CacheAt[tab]or 0)>(tab=="Global"and 45 or 10)or(tab=="Global"and data.SavedAt and os.time()-data.SavedAt>120)then return Client.Stale(data)end
 return data
end
function Client:Fetch(force)
 if not self.Alive or self.Preview or self.Busy or not self.Visible then return end
 local now=os.clock()
 if now<(self.RequestAt or 0)+2.1 then
  if force then self.NextRefresh=math.min(self.NextRefresh,now+2.2) end
  return
 end
 self.RequestAt=now;self.Busy=true;self.Serial+=1
 local serial,tab=self.Serial,self.Tab
 local settled=false
 if not self.Cache[tab] then self.Data={Tab=tab,State="Loading",Rows={}};self.Changed:Fire() end
 local function finish(packet)
  if not self.Alive or serial~=self.Serial or settled then return end
  settled=true
  self.Busy=false
  if type(packet)~="table" or packet.State=="Throttled" then packet={Tab=tab,State="Error",Rows={}} end
  if packet.State=="Error" and self.Cache[tab] then packet=Client.Stale(self.Cache[tab])end
  if packet.State=="Ready" or packet.State=="Empty" then self.Cache[tab]=packet;self.CacheAt[tab]=os.clock()end
  if self.Tab==tab then self.Data=packet;self.NextRefresh=os.clock()+((packet.State=="Error" or packet.State=="Loading")and 10 or tab=="Global"and 45 or 10);self.Changed:Fire()
  else self.NextRefresh=0;self:Fetch(true) end
 end
 task.delay(12,function()if self.Alive and self.Busy and serial==self.Serial then finish({Tab=tab,State="Error",Rows={}})end end)
 task.spawn(function()
  local remote=script.Parent:FindFirstChild("LeaderboardRequest")
  local ok,packet=pcall(function()return remote and remote:InvokeServer(tab)end)
  finish(ok and packet or nil)
 end)
end
function Client:SetVisible(visible)
 if self.Visible==visible then return end
 self.Visible=visible
 if visible then self.Data=self:Cached(self.Tab)or self.Data;self.NextRefresh=0;self:Fetch(true) end
end
function Client:Select(tab)
 if self.Tab==tab then return end
 self.Tab=tab;self.Data=self:Cached(tab) or {Tab=tab,State="Loading",Rows={}};self.NextRefresh=0;self.Changed:Fire();self:Fetch(true)
end
function Client:Step()
 if self.Visible and os.clock()>=self.NextRefresh then self:Fetch() end
end
function Client:Destroy()
 self.Alive=false;self.Serial+=1;if self.ResetConnection then self.ResetConnection:Disconnect()end;self.Changed:Destroy()
end
return Client
