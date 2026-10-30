-- Run in Studio EDIT. Builds real server-shaped Stats and portfolio views from an isolated in-memory engine
-- (restarts, blown attempts, partial closes, copied trades, trimmed/migrated history, legacy practice, open
-- positions), mounts isolated native UI fixtures at desktop and phone sizes and audits the layout.
-- No DataStore, remote or saved-place changes; every temporary object is destroyed on exit.
local shared=game.ReplicatedStorage.MarketReign:Clone() shared.Name="StatsUIValidationModules" shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone() server.Name="StatsUIValidationServer" server.MarketServer.Enabled=false server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui") gui.Name="StatsUIValidation" gui.Parent=game.StarterGui
local function deep(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=deep(x) end return r end
local report={Views=0,Issues={},Data={}}
local decorative={Star=true,Ray=true,Shine=true,Texture=true,LowerEdge=true,Watermark=true}
local function rect(o) local p,s=o.AbsolutePosition,o.AbsoluteSize return p.X,p.Y,p.X+s.X,p.Y+s.Y end
local function shown(o,root) local n=o while n and n~=root do if n:IsA("GuiObject") and not n.Visible then return false end n=n.Parent end return true end
local function skip(o,root) local n=o while n and n~=root do if decorative[n.Name] or n.Name:match("^Star") or n.Name:match("^Diamond") or n.Name=="CandlestickPlot" then return true end n=n.Parent end return false end
local function audit(root,label,mobile)
 local issues={}
 local rx1,ry1,rx2,ry2=rect(root)
 for _,o in ipairs(root.Canvas:GetDescendants()) do
  if o:IsA("GuiObject") and shown(o,root) and not skip(o,root) and o.AbsoluteSize.X>0 then
   local x1,y1,x2,y2=rect(o)
   -- Walk every ancestor: circular-chart masks may sit inside a scrolling page.
   -- Check the clipped rectangle, not the deliberately hidden half of each circle.
   local ancestor=o.Parent local scroll
   while ancestor and ancestor~=root do
    if ancestor:IsA("ScrollingFrame")then scroll=ancestor;break end
    if ancestor:IsA("GuiObject")and ancestor.ClipsDescendants then
     local ax,ay,bx,by=rect(ancestor)
     x1=math.max(x1,ax);y1=math.max(y1,ay);x2=math.min(x2,bx);y2=math.min(y2,by)
    end
    ancestor=ancestor.Parent
   end
   if x2>x1 and y2>y1 then
    if scroll then
     local cx1,_,cx2=rect(scroll)
     if x1<cx1-2 or x2>cx2+2 then table.insert(issues,"horizontal overflow "..o:GetFullName():gsub(".-Canvas%.",""))end
    elseif x1<rx1-2 or y1<ry1-2 or x2>rx2+2 or y2>ry2+2 then table.insert(issues,"offscreen "..o:GetFullName():gsub(".-Canvas%.",""))end
   end
   if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text~="" and o.TextTransparency<1 and not o.TextScaled
    and o.TextTruncate==Enum.TextTruncate.None and not o.TextFits then
    table.insert(issues,"text "..o:GetFullName():gsub(".-Canvas%.","").." '"..o.Text:sub(1,40).."'")
   end
   if mobile and o:IsA("GuiButton") and o.Active and o.BackgroundTransparency<1 and (o.AbsoluteSize.X<32 or o.AbsoluteSize.Y<28) then
    table.insert(issues,"touch "..o:GetFullName():gsub(".-Canvas%.","")..string.format(" %dx%d",o.AbsoluteSize.X,o.AbsoluteSize.Y))
   end
  end
 end
 -- Siblings in the Stats page must not overlap each other (tabs, cards, rows).
 local page=root.Canvas:FindFirstChild("Stats")
 if page then
  local kids={} for _,k in ipairs(page:GetChildren()) do if k:IsA("GuiObject") and k.Visible and not k.Name:match("Depth$") then table.insert(kids,k) end end
  for i=1,#kids do for j=i+1,#kids do
   local a1,b1,c1,d1=rect(kids[i]) local a2,b2,c2,d2=rect(kids[j])
   if a1<c2-1 and a2<c1-1 and b1<d2-1 and b2<d1-1 then table.insert(issues,"overlap "..kids[i].Name.." / "..kids[j].Name) end
  end end
 end
 return issues
end
local ok,err=pcall(function()
 local Engine=require(server.MarketEngine) local Funded=require(server.FundedAccounts) local TradeStats=require(server.TradeStats)
 local UI=require(shared.TerminalUI)
 local Config=deep(require(shared.MarketConfig)) Config.MaxTradeHistory=100000 Config.MaxOrderHistory=100000
 Config.Contracts.BX.Margin=1200
 local Ladder=deep(require(shared.ProgressionConfig))
 local e=Engine.new(Config,91)
 e:AddAccount("maker",1e9,100000,.99,false) e:AddAccount("taker",1e9,100000,.99,false)
 e:AddAccount("player:1:50000",50000,100,Ladder.MarginUse,true)
 local f=Funded.new(e,Ladder,Config) f:Join("1")
 local function quote(side,price,qty) assert(e:Submit("maker",{Contract="BX",Direction=side,Quantity=qty,Type="Limit",Price=price})) end
 local function place(id,side,qty) local okP,r=Funded.Perform(e,id,{Action="Place",Contract="BX",Direction=side,Quantity=qty,Type="Market"}) assert(okP and r.Filled==qty,tostring(r)) end
 local function mark(price) quote(-1,price,1) assert(e:Submit("taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"})) end
 local function round(id,side,entry,exit,qty) qty=qty or 1 quote(-side,entry,qty) place(id,side,qty) quote(side,exit,qty) place(id,-side,qty) end
 local function blow(id,price)
  local drop=math.ceil(e.Accounts[id].Balance/50)+2 -- one BX contract falls far enough to take equity below $0
  quote(-1,price,1) place(id,1,1) mark(price-drop) quote(1,price-drop,1) e:AdvanceClock(.25) f:TakeEvents("1")
  assert(e.Accounts[id].Depleted and not next(e.Accounts[id].Positions),"fixture depletion")
  return price-drop
 end
 assert(f:Select("1","L50000")) round("player:1:50000",1,5825,5830) round("player:1:50000",-1,5830,5832)
 f:Start("1")
 local a1=f:Owner("1") round(a1,1,5825,5827) round(a1,1,5830,5828.5) round(a1,1,5830,5830)
 quote(-1,5830,3) place(a1,1,3) quote(1,5831,1) place(a1,-1,1) quote(1,5832,2) place(a1,-1,2) -- partial close
 blow(a1,5832) assert(f:Restart("1","F5K"))
 local a2=f:Owner("1") local base=e.Books.BX.Last*0.25 for i=1,65 do round(a2,1,base,i%3==0 and base-1 or base+1) end
 e.Accounts[a2].Stats=nil TradeStats.Reconcile(e,e.Accounts[a2],os.time()) -- saved before stats, history trimmed
 local low=blow(a2,base) assert(f:Restart("1","F5K"))
 local p=f:Profile("1") p.Tiers.F10K={State="Unlocked",UnlockedAt=e.Time,Earned=0,Announced=true}
 assert(f:Activate("1","F10K")) assert(f:SetCopy("1",{Enabled=1,Leader="F10K",Followers="F5K",Sizing="Same"}))
 local lead=p.Tiers.F10K.Account
 local req={Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"}
 quote(-1,low,2) local plan=f:Plan("1",lead) local context=f:Context(lead,req) local okL,res=Funded.Perform(e,lead,req) f:Mirror(plan,req,okL,res,context)
 mark(low+10) -- open P&L on both copied positions
 p.Active="F10K"
 e:Audit()
 local rich,view=f:Stats("1"),f:View("1")
 local fresh=Funded.new(e,Ladder,Config) fresh:Start("2") local zero,zeroView=fresh:Stats("2"),fresh:View("2")
 report.Data={All=rich.Scopes[1].Life,Current=rich.Scopes[1].Current,F5K=rich.Scopes[2].Life,Legacy=rich.Legacy[1].Life}
 local sizes={{1920,1022},{1440,900},{1280,720},{1024,600},{844,390},{390,844},{360,640},{320,568}}
 local variants={{"ALL","Life"},{"ALL","Current"},{"F5K","Life"},{"F5K","Current"},{"F10K","Life"},{"L50000","Life"}}
 local states={{"Empty",{Ready=true,New=true,Scopes={},Legacy={}},{New=true,Revision=0}},{"Error",{Error="Stats are temporarily unavailable. Your trades and saved results are not affected."},view},
  {"Loading",{Loading=true},view},{"Zero",zero,zeroView}}
 for _,size in ipairs(sizes) do
  local mobile=size[1]<1000 or size[2]<600
  local function run(label,data,pf,scope,period)
   local holder=Instance.new("Frame") holder.Size=UDim2.fromOffset(size[1],size[2]) holder.Parent=gui
   local c=UI.Mount(holder,{Preview=true,StatsData=data,PortfolioData=pf,StatsScope=scope,StatsPeriod=period})
   task.wait() task.wait()
   local page=c.Root.Canvas:FindFirstChild("Stats")
   local found=audit(c.Root,label,mobile)
   if not page then table.insert(found,"no Stats page") end
   if scope and page and (page:GetAttribute("Scope")~=scope or page:GetAttribute("Period")~=period) then table.insert(found,"scope not applied") end
   local nav=c.Root.Canvas:FindFirstChild("MobileNavigation") or c.Root.Canvas:FindFirstChild("Sidebar")
   if not (nav and nav:FindFirstChild("NavStats")) then table.insert(found,"missing Stats navigation") end
   report.Views+=1
   if #found>0 then table.insert(report.Issues,string.format("%dx%d %s: %s",size[1],size[2],label,table.concat(found," | "))) end
   local state=page and page:GetAttribute("State")
   c:Destroy() holder:Destroy()
   return state
  end
  for _,v in ipairs(variants) do run(v[1]..":"..v[2],rich,view,v[1],v[2]) end
  for _,s in ipairs(states) do local st=run(s[1],s[2],s[3]) local want=s[1]=="Zero" and "Ready" or s[1]
   if st~=want then table.insert(report.Issues,string.format("%dx%d %s state=%s",size[1],size[2],s[1],tostring(st))) end end
 end
end)
gui:Destroy() shared:Destroy() server:Destroy()
if not ok then error(err) end
return report
