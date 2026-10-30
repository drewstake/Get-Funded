-- Visual preview of the Accounts card and Copy Trading popup (Studio Edit mode, MCP or command bar).
-- Defines _G.CopyPreview: Fixture(extra,copyOn), Mount(fixture,x,y,w,h,screen,overlay,picking), Clear().
-- Mounts native fixtures (real FundedAccounts/MarketEngine, Send stubbed) into StarterGui.CopyPreview and
-- hides StarterGui.MarketReign while it is up. Clear() removes everything and restores the saved preview.
if _G.CopyPreview then _G.CopyPreview.Clear() end
local P={};_G.CopyPreview=P
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="CopyPreviewShared";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="CopyPreviewServer";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="CopyPreview";gui.IgnoreGuiInset=true;gui.DisplayOrder=50;gui.Parent=game.StarterGui
local main=game.StarterGui:FindFirstChild("MarketReign");local wasEnabled=main and main.Enabled
if main then main.Enabled=false end
local live={}
function P.Clear()
 for _,c in ipairs(live)do pcall(function()c:Destroy()end)end
 table.clear(live)
 pcall(function()gui:Destroy()end);pcall(function()shared:Destroy()end);pcall(function()server:Destroy()end)
 if main then main.Enabled=wasEnabled end
 _G.CopyPreview=nil
end
function P.Reset()
 for _,c in ipairs(live)do pcall(function()c:Destroy()end)end
 table.clear(live);for _,h in ipairs(gui:GetChildren())do h:Destroy()end
end
local E=require(server.MarketEngine);local F=require(server.FundedAccounts);local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
local M=require(shared.MarketClient);local original=M.New
local current
M.New=function()
 local fx=current;local e,f,uid,p=fx.e,fx.f,fx.uid,fx.p
 local a=e.Accounts[f:Owner(uid)]
 local snapshot=e:Snapshot(a.Id,"BX","1m",true);snapshot.CandlesBySeries={}
 local s=original(nil,true,snapshot)
 s.Preview=false;s.Ready=true;s.CanTrade=true;s.AccountKey=p.Active;s.AccountToken=a.Id
 s.Portfolio=f:View(uid);s.Stats=f:Stats(uid);s.SummaryData=e:Summary(a);s.StatsAt=1
 function s:Send(action,req)table.insert(fx.sends,{Action=action,Req=req});return true,"Sent","Orders",#fx.sends end
 return s
end
local UI=require(shared.TerminalUI)
-- Accounts: $5K (trading, follower), $10K (leader), then 1+extra more $10K accounts.
function P.Fixture(extra,copyOn)
 local e=E.new(C,85);local f=F.new(e,L,C);local uid="preview"
 f:Start(uid);f:Flag(uid,"TutorialDone");f:Flag(uid,"CopyIntro")
 local p=f:Profile(uid);local starter=e.Accounts[f:Owner(uid)]
 starter.Realized=9000;starter.Balance=14000;f:Evaluate(uid)
 f:Activate(uid,"F10K");p.WalletCents=100000000
 for _=1,1+(extra or 0)do f:Purchase(uid,"F10K",p.PurchaseSequence+1)end
 local keys={};for _,entry in ipairs(f:Entries(p))do table.insert(keys,entry.Key)end
 f:SetCopy(uid,{Enabled=copyOn~=false,Leader=keys[2],Followers=keys[1],Sizing="Same"});f:Select(uid,keys[1])
 return{e=e,f=f,uid=uid,p=p,keys=keys,sends={}}
end
function P.Mount(fixture,x,y,w,h,screen,overlay,picking)
 current=fixture
 local host=Instance.new("Frame");host.Name="Host"..(#live+1);host.Position=UDim2.fromOffset(x,y);host.Size=UDim2.fromOffset(w,h)
 host.BackgroundTransparency=1;host.ClipsDescendants=true;host.Parent=gui
 local ctl=UI.Mount(host);table.insert(live,ctl);task.wait();task.wait()
 local st=ctl.State;st.Screen=screen or"Trade";st.Nav=st.Screen;st.Overlay=overlay;st.Sheet=false;st.Toast=nil
 if picking then st.CopyDraft={Leader=fixture.keys[2],Followers={[fixture.keys[1]]=true},Sizing="Same",Picking=true}end
 ctl.Root.UIDiagnostics:Invoke("Render");task.wait();task.wait()
 return ctl
end
return "ready"
