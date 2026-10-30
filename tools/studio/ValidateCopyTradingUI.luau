-- Accounts card and Copy Trading popup validation (Studio Edit mode, command bar or MCP).
-- Native fixtures with the real FundedAccounts/MarketEngine and TerminalUI; only Session:Send is stubbed,
-- and it forwards Copy/Account/Activate/Flag to FundedAccounts like the server does. No remotes,
-- DataStores or player data. Everything it creates is removed. Returns a JSON report.
-- Activation is invoked directly (TestActivate hook); real input routing is checked separately in Play mode.
local H=game:GetService("HttpService")
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="CopyTradingUI";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="CopyTradingUI";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="CopyTradingUI";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub('b%.Activated:Connect%(function%(%.%.%.%)',function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end)
local report={Checks=0,Layouts=0,Issues={},Flows={},Messages={}}
local live={}
local function check(v,msg) report.Checks+=1;assert(v,msg) end
local function deep(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=deep(x)end return o end
local function child(o,name) return o and o:FindFirstChild(name) end
local function audit(root,tag)
 for _,v in ipairs(root:GetDescendants())do
  if (v:IsA("TextLabel")or v:IsA("TextButton")) and v.Visible then
   if v.Text:match("Account #%d")then table.insert(report.Issues,tag.." numbered account label at "..v:GetFullName())end
   if v:IsA("TextLabel") and v.Text~="" and not v.TextFits and not v.TextScaled and v.TextTruncate==Enum.TextTruncate.None then
    table.insert(report.Issues,tag.." text overflow "..(v:GetFullName():gsub(".*Canvas%.","")))
   end
  end
 end
 report.Layouts+=1
end
-- Geometry helpers: UIStroke rims draw outside a control; hover growth scales it about its centre.
local function rim(o) local st=o:FindFirstChild("Border") return st and st:IsA("UIStroke") and st.Thickness or 0 end
local function lift(o)
 if o:GetAttribute("FixedGeometry") then return 0 end
 local s=o.AbsoluteSize;local area=s.X*s.Y
 return (area>18000 and .015 or area>6000 and .025 or .05)*s.X/2
end
local function within(o,clip,pad,vertical)
 local a,b=o.AbsolutePosition,clip.AbsolutePosition;local s,t=o.AbsoluteSize,clip.AbsoluteSize
 local okX=a.X-pad>=b.X-.5 and a.X+s.X+pad<=b.X+t.X+.5
 if not vertical then return okX end
 return okX and a.Y-pad>=b.Y-.5 and a.Y+s.Y+pad<=b.Y+t.Y+.5
end
local ok,err=pcall(function()
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts);local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
 local e=E.new(C,85);local f=F.new(e,L,C);local uid="fixture"
 f:Start(uid);f:Flag(uid,"TutorialDone")
 local p=f:Profile(uid);local starter=e.Accounts[f:Owner(uid)]
 starter.Realized=9000;starter.Balance=14000;f:Evaluate(uid)
 check(p.Tiers.F10K and p.Tiers.F25K,"fixture tiers unlocked")
 check(f:Activate(uid,"F10K"),"activate 10K")
 p.WalletCents=2000000
 local okBuy,msg=f:Purchase(uid,"F10K",p.PurchaseSequence+1);check(okBuy,"buy second 10K: "..tostring(msg))
 local function key(tier,n) local list={} for _,entry in ipairs(f:Entries(p))do if entry.Tier==tier then table.insert(list,entry.Key)end end return list[n] end
 local K5,K10a,K10b=key("F5K",1),key("F10K",1),key("F10K",2)
 check(K5 and K10a and K10b and K10a~=K10b,"two separate $10K instances")
 local function reset() f:SetCopy(uid,{Enabled=true,Leader=K10a,Followers=K5,Sizing="Same"});f:Select(uid,K5) end
 reset()
 local pf=f:View(uid)
 for _,row in ipairs(pf.Accounts)do check(not row.Name:find("#") and not row.Short:find("#"),"server name has sequence: "..row.Name) end
 check(pf.ActiveName=="$5K FUNDED ACCOUNT","active name "..tostring(pf.ActiveName))
 local claimable=0;for _,t in ipairs(pf.Tiers)do if t.Claimable then claimable+=1 end end;check(claimable==1,"F25K should be claimable")
 local sends={};local sessions={}
 local M=require(shared.MarketClient);local original=M.New
 M.New=function()
  local a=e.Accounts[f:Owner(uid)]
  local snapshot=e:Snapshot(a.Id,"BX","1m",true);snapshot.CandlesBySeries={}
  local s=original(nil,true,snapshot);table.insert(sessions,s)
  s.Preview=false;s.Ready=true;s.CanTrade=true;s.AccountKey=p.Active;s.AccountToken=a.Id
  s.Portfolio=f:View(uid);s.Stats=f:Stats(uid);s.SummaryData=e:Summary(a);s.StatsAt=1
  function s:Send(action,req)
   table.insert(sends,{Action=action,Req=deep(req)});local id=#sends
   task.delay(.25,function() -- long enough to observe the pending state
    local yes,message
    if action=="Copy"then yes,message=f:SetCopy(uid,req)
    elseif action=="Account"then yes,message=f:Select(uid,req.Key)
    elseif action=="Activate"then yes,message=f:Activate(uid,req.Tier)
    elseif action=="Flag"then yes,message=f:Flag(uid,req.Stage)
    else yes,message=true,"Fixture" end
    table.insert(report.Messages,action..": "..tostring(message))
    local owner=e.Accounts[f:Owner(uid)]
    s.Portfolio=f:View(uid);s.AccountKey=p.Active;s.AccountToken=owner.Id;s.SummaryData=e:Summary(owner)
    s.Replies:Fire({Kind=action,RequestId=id,Ok=yes,Message=message,Tier=req.Tier,Key=req.Key});s.Changed:Fire()
   end)
   return true,"Sent","Orders",id
  end
  return s
 end
 local UI=require(shared.TerminalUI)
 local function mount(w,h)
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(w,h);host.Parent=gui
  local ctl=UI.Mount(host);table.insert(live,{ctl,host});task.wait();task.wait()
  return ctl,host
 end
 local function settle() task.wait(.4);task.wait();task.wait() end
 local function render(ctl) ctl.Root.UIDiagnostics:Invoke("Render");task.wait();task.wait();check(not ctl.Root:GetAttribute("RenderError"),tostring(ctl.Root:GetAttribute("RenderError"))) end
 local function show(ctl,screen,overlay) ctl.State.Screen=screen;ctl.State.Nav=screen;ctl.State.Overlay=overlay;ctl.State.Sheet=false;ctl.State.Toast=nil;render(ctl) end
 local function click(b) check(b and b:FindFirstChild("TestActivate"),"missing button "..tostring(b and b:GetFullName()));b.TestActivate:Invoke();task.wait();task.wait() end
 local function list(canvas) return canvas.AccountSummary.AccountsCard.AccountList end
 local function rowsOf(canvas) local out={} for _,r in ipairs(list(canvas):GetChildren())do if r:GetAttribute("AccountKey")then out[r:GetAttribute("AccountKey")]=r end end return out end
 local function find(o,name)return o:FindFirstChild(name,true)end
 local function open(ctl)
  ctl.State.CopyDraft=nil;show(ctl,"Trade","Copy");return ctl.Root.Canvas.Dialog.Content
 end
 local function visibleIn(o,parent)
  local a,b=o.AbsolutePosition,parent.AbsolutePosition;local s,t=o.AbsoluteSize,parent.AbsoluteSize
  return a.X>=b.X-1 and a.Y>=b.Y-1 and a.X+s.X<=b.X+t.X+1 and a.Y+s.Y<=b.Y+t.Y+1
 end
 -- Layout, styling, the card-wide Copy Trading action and the popup at every viewport.
 local sizes={{1920,1080},{1440,900},{1280,720},{1024,600},{844,390},{390,844},{360,640},{320,568}}
 for _,size in ipairs(sizes)do
  reset()
  local ctl=mount(size[1],size[2]);local tag=size[1].."x"..size[2];local canvas=ctl.Root.Canvas
  local mobile=size[1]<1000 or size[2]<600
  show(ctl,"Trade");local rows=rowsOf(canvas);local card=canvas.AccountSummary.AccountsCard;local al=list(canvas)
  check(rows[K5] and rows[K10a] and rows[K10b],"all usable accounts listed "..tag)
  check(rows[K5]:GetAttribute("Selected")==true and rows[K10b]:GetAttribute("Selected")==false,"selected marker "..tag)
  check(rows[K5]:FindFirstChild("Dot") and rows[K5].Dot.BackgroundColor3.G>.9,"green active indicator "..tag)
  check(rows[K10a]:FindFirstChild("Name").Text=="$10K FUNDED ACCOUNT" and rows[K10b]:FindFirstChild("Name").Text=="$10K FUNDED ACCOUNT","plain account names "..tag)
  check(rows[K10a].Role.Label.Text=="Leader" and rows[K5].Role.Label.Text=="Follower","saved copy role labels "..tag)
  check(not rows[K10a]:FindFirstChild("Chevron") and not rows[K5]:FindFirstChild("Check"),"roles replace right-side icons "..tag)
  check(not rows[K10b]:FindFirstChild("Role") and rows[K10b]:FindFirstChild("Chevron"),"uninvolved account keeps chevron "..tag)
  check(card.Count.Label.Text=="3","account count "..tag)
  check(card:IsA("GuiButton") and not card:FindFirstChild("OpenCopy"),"card is the entry point, header copy button removed "..tag)
  check(al:GetAttribute("StaticButtons")==true and al:FindFirstChild("ListHitArea"),"list hit area "..tag)
  check(al.ListHitArea.AbsoluteSize.X>=al.AbsoluteSize.X-1 and al.ListHitArea.AbsoluteSize.Y>=al.AbsoluteSize.Y-1,"hit area covers list "..tag)
  -- Styling: no near-white rim, rims inside the clip, whole rows only, nothing overlapping.
  local selRim=rows[K5].Border.Color
  check(math.min(selRim.R,selRim.G,selRim.B)<.55,"selected row rim is not white "..tag)
  check(within(al,card,0,true) and within(card.Count,card,rim(card.Count),true),"list and count inside card "..tag)
  local shown=0
  for k,r in pairs(rows)do
   check(r:GetAttribute("FixedGeometry")==true and not r:FindFirstChild("Shine"),"card row keeps geometry, flat surface "..tag)
   local fully=within(r,al,rim(r),true)
   local away=r.AbsolutePosition.Y-rim(r)>=al.AbsolutePosition.Y+al.AbsoluteSize.Y-.5
   check(fully or away,"row whole or scrolled away "..k.." "..tag)
   if fully then shown+=1 end
   local nm=r:FindFirstChild("Name");local pill=r:FindFirstChild("Role")
   check(nm.TextBounds.X<=nm.AbsoluteSize.X+1,"name fits "..k.." "..tag)
   if pill then
    check((mobile and nm.AbsolutePosition.Y+nm.AbsoluteSize.Y<=pill.AbsolutePosition.Y+1)or(not mobile and nm.AbsolutePosition.X+nm.AbsoluteSize.X<=pill.AbsolutePosition.X-rim(pill)+.5),"name clear of badge "..k.." "..tag)
    check(within(pill,r,rim(pill),true),"badge inside row "..k.." "..tag)
    check(pill.Label.TextBounds.X<=pill.Label.AbsoluteSize.X+1 and pill.Label.TextBounds.Y>=8,"badge text fits "..k.." "..tag)
   end
  end
  check(shown==(mobile and 2 or 3),"whole rows shown ("..shown..") "..tag)
  local goal=canvas.AccountSummary:FindFirstChild("ObjectiveCard")
  if not mobile then
   check(goal,"next unlock card "..tag)
   local t=goal.Title;local l=goal.Label
   check(t.Text:find("\n",1,true) and not t.TextScaled and not l.TextScaled,"goal on two fixed lines "..tag)
   check(t.TextFits and t.TextBounds.X<=t.AbsoluteSize.X+1 and t.TextBounds.Y<=t.AbsoluteSize.Y+1 and t.TextBounds.Y>=t.TextSize*1.8,"two goal lines fit "..tag)
   check(l.AbsolutePosition.Y+l.AbsoluteSize.Y<=t.AbsolutePosition.Y+1 and t.AbsolutePosition.Y+t.AbsoluteSize.Y<=goal.Amount.AbsolutePosition.Y+1,"goal between label and amount "..tag)
   local before={t.TextBounds,l.TextBounds,t.TextSize,t.Text}
   local lift=Instance.new("UIScale");lift.Name="HoverProbe";lift.Scale=1.035;lift.Parent=goal;task.wait();task.wait()
   check(t.Text==before[4] and t.TextSize==before[3],"hover keeps text and size "..tag)
   -- TextBounds are unscaled: identical bounds under the lift mean the text did not re-wrap or re-size.
   check(t.TextBounds==before[1],"hover keeps two-line layout "..tag)
   check(l.TextBounds==before[2],"hover keeps label "..tag)
   report.Flows["goal "..tag]=string.format("%q size %d bounds %s at rest and on hover",t.Text,t.TextSize,tostring(t.TextBounds))
   lift:Destroy();task.wait()
  end
  audit(canvas,tag.." Trade")
  -- Every part of the card opens Copy Trading and never switches the trading account.
  local targets={{"other row",function()return rowsOf(canvas)[K10b]end},{"leader row",function()return rowsOf(canvas)[K10a]end},
   {"trading row",function()return rowsOf(canvas)[K5]end},{"empty list space",function()return list(canvas).ListHitArea end},
   {"card",function()return canvas.AccountSummary.AccountsCard end}}
  for _,t in ipairs(targets)do
   show(ctl,"Trade");local before=#sends;click(t[2]());settle()
   check(#sends==before and ctl.State.Overlay=="Copy" and p.Active==K5,t[1].." opens Copy Trading without switching "..tag)
  end
  check(rowsOf(canvas)[K5]:GetAttribute("Selected")==true,"trading account unchanged "..tag)
  -- Popup: header, corners, rims, spacing and the bounded follower list.
  local dialog=canvas.Dialog;local c=dialog.Content;local hero=dialog.Header;local title=hero.Title
  check(visibleIn(dialog,ctl.Root),"dialog within viewport "..tag)
  check(visibleIn(c.SaveCopy,c),"primary action stays in view "..tag)
  check(not hero:FindFirstChild("Star1"),"no decorative dots in header "..tag)
  local maxSize=title:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize
  check(not title.TextWrapped and title.TextBounds.Y<=maxSize*1.5 and title.TextBounds.X<=title.AbsoluteSize.X+1,"title on one line "..tag)
  check(hero.State.AbsolutePosition.X>=title.AbsolutePosition.X+title.TextBounds.X,"status follows title "..tag)
  check(hero.State.AbsolutePosition.X+hero.State.AbsoluteSize.X+rim(hero.State)+4<=hero.Dismiss.AbsolutePosition.X-rim(hero.Dismiss),"status clear of close "..tag)
  check(within(hero.Dismiss,hero,0,true) and within(hero.State,hero,rim(hero.State),true),"header controls inside header "..tag)
  local corners=0;for _,k in ipairs(c.CopyInfo:GetChildren())do if k:IsA("UICorner")then corners+=1 end end
  check(corners==1 and c.CopyInfo.Corners.CornerRadius.Offset*2>=c.CopyInfo.AbsoluteSize.X,"round info button "..tag)
  local lead=c.LeaderSelector;local first=find(c,"Follow"..K5)
  check(c.SaveCopy.Corners.CornerRadius==lead.Corners.CornerRadius and first.Corners.CornerRadius==lead.Corners.CornerRadius,"one corner radius for rows and action "..tag)
  for _,r in ipairs(c.FollowerList:GetChildren())do if r:IsA("GuiButton")then
   check(within(r,c.FollowerList,rim(r)+lift(r),false),"follower rim and hover room inside list "..r.Name.." "..tag)
   check(not r:FindFirstChild("Shine") and not r:FindFirstChild("LowerEdge"),"flat row surface "..tag)
  end end
  local nm,det=lead:FindFirstChild("Name"),lead.Detail
  local topGap=nm.AbsolutePosition.Y-lead.AbsolutePosition.Y;local bottomGap=lead.AbsolutePosition.Y+lead.AbsoluteSize.Y-(det.AbsolutePosition.Y+det.AbsoluteSize.Y)
  check(math.abs(topGap-bottomGap)<=2,"row text centred "..tag)
  local cue=lead.Change;check(cue.Label.AbsolutePosition.X+cue.Label.TextBounds.X<=cue.AbsolutePosition.X+cue.AbsoluteSize.X-20,"change label clear of chevron "..tag)
  local lastRow=0
  for _,r in ipairs(c.FollowerList:GetChildren())do if r:IsA("GuiButton")and within(r,c.FollowerList,rim(r),true)then lastRow=math.max(lastRow,r.AbsolutePosition.Y+r.AbsoluteSize.Y+rim(r))end end
  check(c.SaveCopy.AbsolutePosition.Y-rim(c.SaveCopy)-lastRow>=6,"room between rows and action "..tag)
  check(c.FollowerList.AbsoluteSize.Y>=first.AbsoluteSize.Y,"one follower fits "..tag)
  check(not find(c,"Follow"..K10a),"source excluded from targets "..tag)
  check(first:GetAttribute("Checked")==true,"saved follower "..tag)
  check(first.Checkbox.Tick:IsA("ImageLabel") and first.Checkbox.Tick.Image=="rbxassetid://87249253289841","generated follower artwork "..tag)
  check(first.Checkbox.Tick.BackgroundTransparency==1 and first.Checkbox.Tick.IsLoaded,"transparent image loaded "..tag)
  check(within(first.Checkbox.Tick,first.Checkbox,0,true),"checkmark inside checkbox "..tag)
  check(not find(c,"Follow"..K10b).Checkbox:FindFirstChild("Tick"),"unchecked follower has no checkmark "..tag)
  check(c.LeaderLabel.Text=="LEADER" and c.FollowLabel.Text=="FOLLOWER(S)","short headings "..tag)
  check(c.SaveCopy.ControlLabel.Text=="Stop Copying","active action "..tag)
  for _,name in ipairs({"Same","Proportional","SizingLabel","RemoveLeader","Rules","Unsaved","LeaderLabelHint","FollowLabelHint"})do check(not find(c,name),"obsolete control "..name.." "..tag)end
  check(hero.State.Label.Text=="ON","header status "..tag)
  click(c.LeaderSelector);c=canvas.Dialog.Content
  check(c.LeaderChoices and visibleIn(c.LeaderChoices,c),"bounded source dropdown "..tag)
  for _,r in ipairs(c.LeaderChoices:GetChildren())do if r:IsA("GuiButton")then
   check(within(r,c.LeaderChoices,rim(r),false),"choice rim inside dropdown "..tag)
   local b=r:FindFirstChild("Balance");check(b and b.TextFits and b.TextBounds.Y>=(mobile and 10 or 12) and within(b,r,0,true),"picker balance readable "..tag)
  end end
  local function balances(editor,where)
   check(not find(editor,"CopyHint"),"copy hint removed "..where)
   local tip=find(editor,"CopyRules");check(tip and not tip.Text.Text:find("Only new trades",1,true),"rules no longer repeat the hint "..where)
   for _,r in ipairs(editor:GetDescendants())do
    if r:IsA("GuiButton") and r:FindFirstChild("Detail") and r:FindFirstChild("Name") then
     local d,n=r.Detail,r:FindFirstChild("Name")
     check(d.TextFits and d.TextBounds.Y>=(mobile and 11 or 13),"balance readable "..r.Name.." "..where)
     check(d.AbsolutePosition.Y>=n.AbsolutePosition.Y+n.AbsoluteSize.Y-1 and within(d,r,0,true),"balance below name, inside row "..r.Name.." "..where)
     local box=r:FindFirstChild("Checkbox") or r:FindFirstChild("Change")
     if box then check(d.AbsolutePosition.X+d.TextBounds.X<=box.AbsolutePosition.X-rim(box) and n.AbsolutePosition.X+n.TextBounds.X<=box.AbsolutePosition.X-rim(box),"name and balance clear of control "..r.Name.." "..where)end
    end
   end
  end
  balances(canvas.Dialog.Content,tag.." popup")
  audit(dialog,tag.." Copy")
  show(ctl,"Dashboard");local cc=canvas.Dashboard.CopyTrading
  check(cc.LeaderSelector:GetAttribute("AccountKey")==K10a and find(cc,"Follow"..K5):GetAttribute("Checked"),"shared editor "..tag)
  check(not find(cc,"SizingLabel") and not find(cc,"RemoveLeader"),"simplified Accounts tab "..tag)
  check(cc.LeaderLabel.Text=="LEADER" and cc.FollowLabel.Text=="FOLLOWER(S)","Accounts headings "..tag)
  check(find(cc,"Follow"..K5).Checkbox.Tick.Image=="rbxassetid://87249253289841","same checkmark in both editors "..tag)
  balances(cc,tag.." Accounts tab")
  for _,row in ipairs(pf.Accounts)do
   local owned=canvas.Dashboard:FindFirstChild("Tier"..row.Key)
   check(owned and not owned:FindFirstChild("Action"),"owned account trade action removed "..tag)
   -- Usable owned cards: no OWNED chip and no open-position row; the copy role sits beside the Balance label.
   check(not owned:FindFirstChild("Status") and not owned:FindFirstChild("Open"),"owned card has no status chip or open row "..tag)
   check(owned:FindFirstChild("Balance") and owned:FindFirstChild("Realized"),"owned card keeps both balances "..tag)
   local pill=owned:FindFirstChild("Role")
   check((pill~=nil)==(row.Role~=nil),"role chip only while copying "..tag)
   if pill then
    check(within(pill,owned,rim(pill),true),"role chip inside card "..tag)
    local beside=owned:FindFirstChild("BalanceLabel") or owned:FindFirstChild("Size")
    check(beside.AbsolutePosition.X+beside.TextBounds.X<=pill.AbsolutePosition.X-rim(pill),"role chip clear of text "..tag)
   end
   local balance=owned.Balance;local title=owned:FindFirstChild("Size")
   check(balance.AbsolutePosition.Y>=title.AbsolutePosition.Y+title.AbsoluteSize.Y-1,"balances start below the name "..tag)
   check(balance.AbsolutePosition.Y-(title.AbsolutePosition.Y+title.AbsoluteSize.Y)<=(owned:FindFirstChild("BalanceLabel") and 32 or 8),"no empty band under the name "..tag)
   local bottom=owned:FindFirstChild("ResetAccount")or owned.Realized
   check(owned.AbsoluteSize.Y-(bottom.Position.Y.Offset+bottom.Size.Y.Offset)<=16,"no empty area at the bottom "..tag)
  end
  audit(canvas.Dashboard,tag.." Accounts")
  -- Switching the trading account still works from the account switcher.
  show(ctl,"Trade","Accounts");local before=#sends;click(find(canvas.Dialog.Content,"Account"..K10b));settle()
  check(#sends==before+1 and sends[#sends].Action=="Account" and p.Active==K10b,"account switcher still switches "..tag)
  ctl:Destroy()
 end
 report.SizesPassed=#sizes
 -- Start / edit / save / stop, duplicate identities, pending guard, and draft discard.
 for _,size in ipairs({{1440,900},{390,844},{320,568}})do
  reset();local ctl=mount(size[1],size[2]);local canvas=ctl.Root.Canvas;local tag=size[1].."x"..size[2]
  local c=open(ctl)
  click(find(c,"Follow"..K10b));c=canvas.Dialog.Content
  check(find(c,"Follow"..K10b).Checkbox:FindFirstChild("Tick"),"checking follower shows image")
  check(c.SaveCopy.ControlLabel.Text=="Save Changes" and c.StopCopy,"edited setup retains stop action")
  check(c.StopCopy.Corners.CornerRadius==c.SaveCopy.Corners.CornerRadius,"stop and save share corners")
  check(not table.find(p.Copy.Followers,K10b),"draft must not reach server")
  c=open(ctl);check(not find(c,"Follow"..K10b):GetAttribute("Checked"),"reopen discards draft")
  check(not find(c,"Follow"..K10b).Checkbox:FindFirstChild("Tick"),"discard clears image")
  click(find(c,"Follow"..K10b));c=canvas.Dialog.Content
  local before=#sends;click(c.SaveCopy);check(canvas.Dialog.Content.SaveCopy.ControlLabel.Text=="Saving…","pending label")
  click(canvas.Dialog.Content.SaveCopy);check(#sends==before+1,"pending blocks duplicate send");settle()
  check(table.find(p.Copy.Followers,K10b) and canvas.Dialog.Content.SaveCopy.ControlLabel.Text=="Stop Copying","save applied")
  c=canvas.Dialog.Content;click(c.LeaderSelector);click(find(canvas.Dialog.Content,"ChooseLeader"..K10b));c=canvas.Dialog.Content
  check(not find(c,"Follow"..K10b) and find(c,"Follow"..K5):GetAttribute("Checked"),"new source excluded and other checks kept")
  click(c.SaveCopy);settle();check(p.Copy.Leader==K10b,"second same-size account becomes source")
  c=canvas.Dialog.Content;click(find(c,"Follow"..K5));c=canvas.Dialog.Content
  check(not c.SaveCopy.Active and c.StopCopy.Active,"empty active draft can still stop")
  click(c.StopCopy);settle();check(not p.Copy.Enabled,"stop applied")
  for _,row in pairs(rowsOf(canvas))do check(not row:FindFirstChild("Role"),"role badges clear when copying stops")end
  c=canvas.Dialog.Content;check(c.SaveCopy.ControlLabel.Text=="Start Copying","saved selection retained while off")
  local hero=canvas.Dialog.Header
  check(hero.State.Label.Text=="OFF","header status off")
  check(hero.State.AbsolutePosition.X>=hero.Title.AbsolutePosition.X+hero.Title.TextBounds.X and hero.Title.TextBounds.X<=hero.Title.AbsoluteSize.X+1,"off status follows title "..tag)
  click(c.SaveCopy);settle();check(p.Copy.Enabled and p.Copy.Leader==K10b,"restart retained setup")
  show(ctl,"Dashboard");local cc=canvas.Dashboard.CopyTrading
  check(cc.LeaderSelector:GetAttribute("AccountKey")==K10b,"Accounts tab reflects saved setup")
  click(cc.SaveCopy);settle();check(not p.Copy.Enabled,"stop from Accounts tab")
  report.Flows[tag]="discard draft, save, duplicate-send guard, change source, stop incomplete draft, restart, cross-entry sync passed"
  ctl:Destroy()
 end
 -- Existing proportional setups are preserved although their control has been removed.
 f:SetCopy(uid,{Enabled=true,Leader=K10a,Followers=K5,Sizing="Proportional"})
 local ctl=mount(1440,900);local c=open(ctl)
 click(find(c,"Follow"..K10b));click(ctl.Root.Canvas.Dialog.Content.SaveCopy);settle()
 check(sends[#sends].Req.Sizing=="Proportional" and p.Copy.Sizing=="Proportional","hidden sizing must not change")
 ctl:Destroy()
 -- A fresh setup, without a retained leader, cannot start until both choices exist.
 p.Copy={Enabled=false,Followers={},Sizing="Same"}
 ctl=mount(390,844);c=open(ctl)
 check(not c.SaveCopy.Active and c.SaveCopy.ControlLabel.Text=="Choose an account","fresh setup")
 click(c.LeaderSelector);click(find(ctl.Root.Canvas.Dialog.Content,"ChooseLeader"..K10b));c=ctl.Root.Canvas.Dialog.Content
 check(not c.SaveCopy.Active,"requires destination")
 click(find(c,"Follow"..K10a));click(ctl.Root.Canvas.Dialog.Content.SaveCopy);settle()
 check(p.Copy.Enabled and p.Copy.Leader==K10b and p.Copy.Followers[1]==K10a,"start fresh setup")
 ctl:Destroy()
 -- Overflow: both lists scroll whole rows while the action stays fixed at every viewport.
 p.WalletCents=100000000
 for _=1,4 do check(f:Purchase(uid,"F10K",p.PurchaseSequence+1),"overflow fixture purchase")end
 for _,size in ipairs(sizes)do
  local tag="overflow "..size[1].."x"..size[2];local mobile=size[1]<1000 or size[2]<600
  ctl=mount(size[1],size[2]);c=open(ctl)
  local al=list(ctl.Root.Canvas)
  check(al.CanvasSize.Y.Offset>al.Size.Y.Offset and al.ScrollBarThickness>0,"card list scrolls "..tag)
  local shown=0;for _,r in ipairs(al:GetChildren())do if r:GetAttribute("AccountKey")and within(r,al,rim(r),true)then shown+=1 end end
  check(shown==(mobile and 2 or 3),"card shows whole rows "..tag)
  check(al.ListHitArea.AbsoluteSize.Y>=al.CanvasSize.Y.Offset-1,"hit area spans the scrolled list "..tag)
  local fl=c.FollowerList
  check(fl.CanvasSize.Y.Offset>fl.Size.Y.Offset and fl.ScrollBarThickness>0,"followers scroll "..tag)
  for _,r in ipairs(fl:GetChildren())do if r:IsA("GuiButton")then
   local away=r.AbsolutePosition.Y-rim(r)>=fl.AbsolutePosition.Y+fl.AbsoluteSize.Y-.5
   check(within(r,fl,rim(r),true)or away,"followers show whole rows "..r.Name.." "..tag)
   check(within(r,fl,rim(r)+lift(r),false),"scrollbar clear of rows "..tag)
  end end
  check(visibleIn(c.SaveCopy,c),"overflow action visible "..tag)
  local lastKey=key("F10K",6)
  fl.CanvasPosition=Vector2.new(0,10000);task.wait()
  click(find(c,"Follow"..lastKey));c=ctl.Root.Canvas.Dialog.Content
  check(find(c,"Follow"..lastKey):GetAttribute("Checked"),"last follower selectable "..tag)
  check(c.FollowerList.CanvasPosition.Y>0,"follower scroll retained after toggle "..tag)
  audit(ctl.Root.Canvas.Dialog,tag);ctl:Destroy()
 end
 report.OverflowSizesPassed=#sizes
 -- Existing account activation remains reachable.
 ctl=mount(1440,900);show(ctl,"Dashboard")
 click(ctl.Root.Canvas.Dashboard.TierF25K.Action);settle()
 check(sends[#sends].Action=="Activate" and p.Tiers.F25K.Claimed,"free activation unchanged")
 ctl:Destroy()

 -- Longest tier names and trade-ticket cleanup, with real $50K/$100K instances.
 starter.Realized=100000;starter.Balance=105000;f:Evaluate(uid)
 check(f:Activate(uid,"F50K"),"activate 50K layout fixture")
 check(f:Activate(uid,"F100K"),"activate 100K layout fixture")
 local K50,K100=key("F50K",1),key("F100K",1)
 check(f:SetCopy(uid,{Enabled=true,Leader=K100,Followers=K50,Sizing="Same"}),"long-name copy fixture")
 check(f:Select(uid,K100),"long-name trading account")
 for _,size in ipairs(sizes)do
  ctl=mount(size[1],size[2]);local tag="long names "..size[1].."x"..size[2]
  local canvas=ctl.Root.Canvas
  for _,screen in ipairs({"Trade","Dashboard","Shop","Stats"})do
   show(ctl,screen)
   audit(canvas,tag.." "..screen)
   for _,label in ipairs(canvas:GetDescendants())do
    if label:IsA("TextLabel") and label.Text:find("FUNDED ACCOUNT",1,true)then
     check(label.TextBounds.X<=label.AbsoluteSize.X+1 and label.TextBounds.Y<=label.AbsoluteSize.Y+1,"full funded name fits "..label:GetFullName().." "..tag)
    end
   end
   local ticket=canvas:FindFirstChild("OrderTicket")or canvas:FindFirstChild("TradeDock")
   if ticket then for _,label in ipairs(ticket:GetDescendants())do if label:IsA("TextLabel")then
    check(not label.Text:lower():find("copy") and not label.Text:lower():find("follows"),"no copy destination in trade controls "..tag)
   end end end
  end
  c=open(ctl)
  local label=c.LeaderSelector:FindFirstChild("Name")
  check(label.Text=="$100K FUNDED ACCOUNT" and label.TextBounds.X<=label.AbsoluteSize.X+1 and label.TextBounds.Y<=label.AbsoluteSize.Y+1,"longest leader name fits "..tag)
  check(find(c,"Follow"..K50):FindFirstChild("Name").Text=="$50K FUNDED ACCOUNT","50K follower name "..tag)
  audit(canvas.Dialog,tag.." Copy")
  ctl:Destroy()
 end

end)
for _,item in ipairs(live)do pcall(function()item[1]:Destroy();item[2]:Destroy()end)end
gui:Destroy();shared:Destroy();server:Destroy()
if not ok then report.Error=tostring(err)end
return H:JSONEncode(report)
