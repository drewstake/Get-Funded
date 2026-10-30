-- Disposable test harness. The injected marketplace never opens a real purchase prompt.
local shared=game.ReplicatedStorage.MarketReign
local Purchase=require(shared.DepthPurchase)
local report={Checks={},Layouts={}}
local function check(name,ok)assert(ok,name);table.insert(report.Checks,name)end
local ok,err=xpcall(function()
 local event=Instance.new("BindableEvent")
 local clock=0;local calls=0;local prompts=0;local broken=false;local promptBroken=false;local sale=false
 local player=game.Players.LocalPlayer;local session={DepthAccess={Allowed=false,State="Locked",PassId=2006894567}}
 local api={PromptGamePassPurchaseFinished=event.Event,
  GetProductInfoAsync=function(_,id,kind)
   calls+=1;assert(id==2006894567 and kind==Enum.InfoType.GamePass)
   if broken then error("Injected metadata failure")end
   return {IsForSale=sale,IconImageAssetId=90643097876584}
  end,
  PromptGamePassPurchase=function(_,p,id)
   assert(p==player and id==2006894567);prompts+=1
   if promptBroken then error("Injected prompt failure")end
  end}
 local function settle()task.wait()end
 local p=Purchase.new(session,false,function()end,{Marketplace=api,Player=player,Clock=function()return clock end})
 check("Unloaded pass cannot prompt",not p:State().Enabled)
 p:Refresh();settle()
 check("Off-sale metadata disables purchases",p:State().Label=="Not on sale"and not p:State().Enabled)
 check("Official pass icon is used",p:State().Icon=="rbxassetid://90643097876584")
 p:Prompt();check("Off-sale prompt is blocked",prompts==0)
 p:Refresh();check("Metadata is cached",calls==1)
 sale=true;clock=31;p:Refresh();settle()
 check("Turning on sales enables unlock after metadata refresh",p:State().Enabled and p:State().Label=="Unlock L2")
 p:Prompt();p:Prompt();check("Correct pass opens once; repeated taps are ignored",prompts==1 and p:State().Label=="Opening Roblox…")
 event:Fire(player,2006894567,false);settle()
 check("Cancel restores unlock without granting access",p:State().Enabled and not session.DepthAccess.Allowed)
 p:Prompt();event:Fire(player,1,true);settle()
 check("Unrelated purchase events are ignored",p.Prompting==true)
 event:Fire(player,2006894567,true);settle()
 check("Client purchase success only shows verification; it never grants ownership",not session.DepthAccess.Allowed and p:State().Label=="Checking access…"and not p:State().Enabled)
 clock+=21;check("Unverified purchase never becomes owned",p:State().Label=="Unlock L2"and not session.DepthAccess.Allowed)
 session.DepthAccess={Allowed=true,State="Owned",PassId=2006894567}
 check("Only server entitlement shows owned",p:State().Label=="Owned"and not p:State().Enabled)
 local count=prompts;p:Prompt();check("Owners cannot buy again",prompts==count)
 session.DepthAccess={Allowed=false,State="Checking",PassId=2006894567}
 check("Pending ownership blocks the prompt",not p:State().Enabled)
 session.DepthAccess.State="Unavailable";check("Ownership errors block the prompt",not p:State().Enabled)
 session.DepthAccess.State="Locked";broken=true;p:Refresh(true);settle()
 check("Metadata errors expose an honest retry",p:State().Label=="Retry"and p:State().Enabled)
 broken=false;p:Prompt();settle();check("Retry fetches metadata without opening a purchase",p:State().Label=="Unlock L2"and prompts==count)
 promptBroken=true;p:Prompt();check("Prompt failure is recoverable",p:State().Label=="Retry unlock"and p:State().Enabled)
 promptBroken=false;p:Prompt();event:Fire(player,2006894567,false);settle()
 local preview=Purchase.new(session,true,nil,{Marketplace=api,Player=player});count=prompts
 preview:Refresh();preview:Prompt();check("Edit preview cannot purchase",prompts==count and preview:State().Label=="Play to unlock")
 preview:Destroy();p:Destroy();event:Destroy()

 -- Exercise the actual Shop renderer and update method at narrow and wide widths.
 local Shop=require(shared.ShopView)
 local gui=Instance.new("ScreenGui");gui.Name="DepthPassLayoutTest";gui.Enabled=false;gui.Parent=game.Players.LocalPlayer.PlayerGui
 local canvas=Instance.new("Frame");canvas.Parent=gui;canvas.Size=UDim2.fromScale(1,1)
 local function button(parent,name,value,x,y,w,h,callback,bg,fg,size,z)
  local b=Instance.new("TextButton");b.Name=name;b.Text=value;b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.TextSize=size or 20;b.ZIndex=z or 45;b.Parent=parent
  b.Activated:Connect(callback);return b
 end
 local function gloss(b)
  local edge=Instance.new("UIStroke");edge.Name="Border";edge.Parent=b
  local t=Instance.new("TextLabel");t.Name="ControlLabel";t.Text=b.Text;t.Size=UDim2.fromScale(1,1);t.Font=Enum.Font.FredokaOne;t.TextSize=b.TextSize;t.Parent=b
  return b
 end
 for _,size in ipairs({{320,568},{390,844},{749,303},{1280,720},{1920,1080}})do
  local dialog=Shop.Draw({Canvas=canvas,button=button,gloss=gloss,
   dismiss=function(parent,x,y,s,fn,z)return button(parent,"CloseShop","X",x,y,s,s,fn,nil,nil,20,z)end,
   shopIcon=function()end,close=function()end,
   depthState=function()return {Label="Not on sale",Enabled=false,Note="This pass is not on sale yet."}end},size[1],size[2])
  task.wait()
  local hero=dialog.ShopCatalog.MarketDepthPro;local b=hero.Availability
  local identity=b
  for _,label in ipairs({"Unlock L2","Checking access…","Access unavailable","Opening Roblox…","Not on sale","Owned","Retry unlock"})do
   Shop.UpdateDepth(dialog,{Label=label,Enabled=label=="Unlock L2",Note="Roblox confirms the price before you buy."});task.wait()
   check("Readable "..label.." at "..size[1],b.ControlLabel.TextFits and hero.PurchaseNote.TextFits)
  end
  check("Shop updates reuse purchase control "..size[1],hero.Availability==identity)
  check("Other passes remain unavailable "..size[1],not dialog.ShopCatalog.VIPTrader.Availability.Interactable)
  check("Catalog has usable scroll area "..size[1],dialog.ShopCatalog.AbsoluteSize.Y>0 and dialog.ShopCatalog.CanvasSize.Y.Offset>=hero.Size.Y.Offset)
  if size[1]<720 or size[2]<400 then check("Compact catalog can scroll "..size[1],dialog.ShopCatalog.CanvasSize.Y.Offset>dialog.ShopCatalog.Size.Y.Offset)end
  local cp=dialog.CloseShop.Position;local cs=dialog.CloseShop.Size
  check("Close stays within fixed header "..size[1],cp.X.Offset>=0 and cp.Y.Offset>=0 and cp.X.Offset+cs.X.Offset<=dialog.Size.X.Offset and cp.Y.Offset+cs.Y.Offset<=dialog.ShopCatalog.Position.Y.Offset)
  table.insert(report.Layouts,{Width=size[1],Height=size[2],ButtonWidth=b.Size.X.Offset,ButtonHeight=b.Size.Y.Offset})
  dialog:Destroy()
 end
 gui:Destroy()
end,debug.traceback)
report.Ok=ok;report.Error=not ok and err or nil
local value=Instance.new("StringValue");value.Name="DepthPassClientResult";value.Value=game:GetService("HttpService"):JSONEncode(report);value.Parent=shared
print("DEPTH_PASS_CLIENT "..value.Value)
