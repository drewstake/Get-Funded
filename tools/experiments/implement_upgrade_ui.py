from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sub(s,a,b):
 assert a in s,a[:160]
 return s.replace(a,b)
p=ROOT/'src/shared/TerminalUI.luau';s=p.read_text(encoding='utf-8')
s=sub(s,'local ProgressView = require(script.Parent.ProgressView)','local ProgressView = require(script.Parent.ProgressView)\nlocal BadgeArt=require(script.Parent.BadgeArt)\nlocal AwayView=require(script.Parent.AwayView)')
s=sub(s,'return "Free $10K restart",s.PendingRestart~=nil','return "Restart · "..whole((session.Portfolio or {}).StartingBalance or Ladder.StartingBalance),s.PendingRestart~=nil')
s=sub(s,'fail("Restart free with $10,000 after your account fails.")','fail("Restart with your earned starting balance after your account fails.")')
s=sub(s,'local function overlay(w,h)\n  if not s.Overlay then return end','''local function overlay(w,h)
  if not s.Overlay then return end
  if s.Overlay=="Away" then
   local away=session.Portfolio and session.Portfolio.AwaySummary
   if not away then s.Overlay=nil;return end
   button(canvas,"AwayBackdrop","",0,0,w,h,function()end,C.Bg,C.Text,12,40).BackgroundTransparency=.25
   AwayView.Draw({Canvas=canvas,C=C,frame=frame,text=text,round=round,stroke=stroke,tint=tint,button=button,gloss=glossy,signed=Market.Signed},w,h,away,function()
    local ok,message=session:AcknowledgeAway(away.Id)
    if not ok then fail(message);return end
    s.AwaySeen=away.Id;s.Overlay=nil;refresh()
   end)
   return
  end''')
s=sub(s,'if s.Overlay=="QuantityLimit"then','''if s.Overlay=="ResetAccount"then
   local balance=pf and pf.StartingBalance or Ladder.StartingBalance
   local _,p=popupShell(w,h,pw,326,"Reset Account?","Accounts","Keep your permanent progress")
   optionLabel(p,"StartingBalance","Start with "..whole(balance),pad,0,iw,40,narrow and 22 or 28,C.Green)
   body(p,"ResetEffects","Your current balance is replaced. Open positions and pending orders are cleared without counting as completed trades. Current account statistics start over.",pad,52,iw,105,15)
   body(p,"Preserved","Lifetime statistics, milestones, permanent starting-balance bonuses and rank progression stay yours.",pad,164,iw,78,15)
   local bw=(iw-10)/2
   popupButton(p,"CancelReset","Cancel",pad,260,bw,48,close,"Navy",18)
   local confirm=popupButton(p,"ConfirmReset",s.PendingReset and "Resetting…"or "Reset Account",pad+bw+10,260,bw,48,function()
    if s.PendingReset then return end
    local ok,message,_,id=session:ResetAccount()
    if not ok then fail(message);return end
    s.PendingReset=id;refresh()
    task.delay(10,function()if alive and s.PendingReset==id then s.PendingReset=nil;fail("Reset confirmation has not arrived. Check the account before retrying.")end end)
   end,"Pink",narrow and 15 or 18)
   confirm.Active=not s.PendingReset
  elseif s.Overlay=="QuantityLimit"then''')
s=sub(s,'{"Settings","Settings","Settings"}}','{"ResetAccount","Reset Account","Accounts"},{"Settings","Settings","Settings"}}')
s=sub(s,'"Restart free with $10,000 in-game money. Keep your ranks, titles and lifetime totals. Losses still count toward lifetime net profit."','"Restart with "..whole((pf or {}).StartingBalance or Ladder.StartingBalance).." in-game money. Keep ranks, milestones, permanent bonuses and lifetime totals."')
s=sub(s,'"Lifetime net profit standings"','"Account balance standings"')
s=sub(s,'StartingBalance=Ladder.StartingBalance','StartingBalance=(session.Portfolio or {}).StartingBalance or Ladder.StartingBalance')
start=s.index('   local marketY=74+5*(navH+9)+10')
end=s.index('   local settings=button(rail,"Settings"',start)
s=s[:start]+'''   local marketY=74+5*(navH+9)+10
   local marketH=h>=900 and 42 or 34
   local stacked=marketY+29+#Market.ContractOrder*(marketH+8)+58<rh-116
   local rankY=marketY
   if screen=="Trade"then
    sidebarText(rail,"Markets","YOUR MARKETS",14,marketY,rw-28,22,14,SB.Muted)
    local count=#Market.ContractOrder;local cell=(rw-24-(count-1)*4)/count
    for i,key in ipairs(Market.ContractOrder)do
     local selected=key==s.Contract
     local bx=stacked and 12 or 12+(i-1)*(cell+4)
     local by=marketY+29+(stacked and (i-1)*(marketH+8)or 0)
     local bw=stacked and rw-24 or cell
     local b=button(rail,"Market"..key,"",bx,by,bw,marketH,function()selectContract(key)end,Color3.new(1,1,1),C.Text,12,3)
     sidebarSurface(b,selected,true);if fx then fx:Selected(b,selected)end
     sidebarText(b,"Symbol",key,stacked and 16 or 4,0,bw-8,marketH,stacked and 21 or 16)
    end
    rankY=marketY+29+(stacked and count*(marketH+8)or marketH+8)
   end
   BadgeArt.Create(rail,"SidebarRankBadge",session.Portfolio and session.Portfolio.RankBadge or 1,12,rankY+4,36)
   local rank=sidebarText(rail,"Rank",session.Portfolio and session.Portfolio.Rank or "Market Rookie",54,rankY,rw-66,48,rw<180 and 14 or 17,Color3.fromRGB(255,225,80));rank.TextWrapped=true
   local reset=button(rail,"ResetAccount","",12,rh-107,rw-24,42,function()s.Overlay="ResetAccount";refresh()end,false,C.Text,12,3)
   sidebarImage(reset,"Accounts",0,3,36);sidebarText(reset,"Label","Reset Account",40,0,rw-64,42,rw<180 and 15 or 18)
'''+s[end:]
s=sub(s,'  overlay(w,h)','  local away=session.Portfolio and session.Portfolio.AwaySummary\n  if away and s.AwaySeen~=away.Id then s.Overlay="Away"end\n  overlay(w,h)')
s=sub(s,'   if currentScreen()=="Leaderboard"then return end','   if currentScreen()=="Leaderboard"then\n    local pf=session.Portfolio;local rail=canvas:FindFirstChild("Sidebar")\n    if rail and pf and rail.Rank.Text~=pf.Rank then refresh()end\n    return\n   end')
s=sub(s,'   chartView:OnReply(reply)','   if reply.Kind=="AcknowledgeAway"then\n    if not reply.Ok then s.AwaySeen=nil;refresh()end\n    return\n   end\n   if reply.Kind=="ResetAccount"then\n    s.PendingReset=nil\n    if reply.Ok then s.Overlay=nil;blownQueue={};s.CoachDismissed=true end\n   end\n   chartView:OnReply(reply)')
s=sub(s,'elseif reply.Kind=="Restart"and reply.Ok then','elseif (reply.Kind=="Restart"or reply.Kind=="ResetAccount")and reply.Ok then')
p.write_text(s,encoding='utf-8')

p=ROOT/'src/shared/ProgressView.luau';s=p.read_text(encoding='utf-8')
s=sub(s,'yy=44;yy+=copy(content,"Subtitle","Build your record. Earn ranks and titles that stay yours.",0,yy,cw,14,C.Muted)+12','yy=44;yy+=copy(content,"Subtitle","Build your record. Earn ranks, titles and permanent starting funds.",0,yy,cw,14,C.Muted)+8\n  yy+=copy(content,"StartingBalance","Starting balance: "..whole(pf.StartingBalance or Config.StartingBalance).." · includes +"..whole(pf.StartingBonus or 0).." permanent bonus",0,yy,cw,16,C.Green)+12')
s=sub(s,'local permanentH=height("Earned titles stay yours.",12,nw-32)','local rewardText=n and "+"..whole(n.StartingBonus or 0).." starting balance · permanent"or "All starting-balance bonuses earned"\n  local permanentH=height(rewardText,12,nw-32)')
s=sub(s,'label(nextCard,"Permanent","Earned titles stay yours."','label(nextCard,"Permanent",rewardText')
s=sub(s,'Each goal earns a title.','Each goal earns a title and a permanent starting-balance bonus.')
s=sub(s,'collection=="Titles" and m.Name or starter','collection=="Titles" and (m.Name.."\\n+"..whole(m.StartingBonus or 0).." starting balance · permanent") or starter')
s=sub(s,'height(m.Name,14,tileW-28)','height(m.Name.."\\n+"..whole(m.StartingBonus or 0).." starting balance · permanent",14,tileW-28)')
p.write_text(s,encoding='utf-8')
