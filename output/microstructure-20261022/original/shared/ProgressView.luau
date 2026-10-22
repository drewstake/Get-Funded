-- One next rank with every lifetime requirement, followed by the title collection.
local TextService=game:GetService("TextService")
local TweenService=game:GetService("TweenService")
local Art=require(script.Parent.BadgeArt)
local Config=require(script.Parent.ProgressionConfig)
local View={}
local F=Enum.Font.FredokaOne
local C={Text=Color3.fromRGB(245,248,255),Muted=Color3.fromRGB(204,222,251),Surface=Color3.fromRGB(6,30,74),
 Edge=Color3.fromRGB(46,89,152),Gold=Color3.fromRGB(255,216,74),Cyan=Color3.fromRGB(76,223,255),Purple=Color3.fromRGB(178,126,255),Green=Color3.fromRGB(75,240,174)}
local function make(class,name,parent,props)
 local o=Instance.new(class);o.Name=name;for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o
end
local function box(p,name,x,y,w,h,color)
 return make("Frame",name,p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color or C.Surface,BorderSizePixel=0})
end
local function round(p,r)make("UICorner","Corners",p,{CornerRadius=UDim.new(0,r)})end
local function card(p,name,x,y,w,h,edge)
 local o=box(p,name,x,y,w,h);round(o,14)
 make("UIStroke","Border",o,{Color=edge or C.Edge,Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 return o
end
local function typeSize(size)
 return size<=18 and size*1.125 or math.round(size*1.07)
end
local function label(p,name,value,x,y,w,h,size,color)
 return make("TextLabel",name,p,{Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
 TextColor3=color or C.Text,TextSize=typeSize(size),Font=F,TextStrokeColor3=Color3.fromRGB(1,15,49),TextStrokeTransparency=.85,
 TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true,TextScaled=false,LineHeight=1.12})
end
local function height(value,size,w)return math.ceil(TextService:GetTextSize(value,typeSize(size),F,Vector2.new(math.max(1,w-4),10000)).Y*1.12)+8 end
local function copy(p,name,value,x,y,w,size,color)
 local h=height(value,size,w);label(p,name,value,x,y,w,h,size,color);return h
end
local function bar(p,name,x,y,w,ratio)
 local track=box(p,name,x,y,w,7,Color3.fromRGB(27,53,96));round(track,4)
 ratio=math.clamp(ratio,0,1);track:SetAttribute("Progress",ratio)
 local fill=box(track,"Fill",0,0,w*ratio,7,C.Cyan);round(fill,4);fill.Visible=ratio>0
end
local function hover(p,icon)
 local base=p.Border.Color
 local function active(on)
  TweenService:Create(p.Border,TweenInfo.new(.13),{Color=on and C.Cyan or base,Thickness=on and 2.5 or 1.5}):Play()
  if icon then TweenService:Create(icon,TweenInfo.new(.13),{Rotation=on and -3 or 0}):Play()end
 end
 p.MouseEnter:Connect(function()active(true)end);p.MouseLeave:Connect(function()active(false)end)
end
local function amount(m,whole)
 return m.Kind=="Profit" and whole(m.Progress or 0).." / "..whole(m.Goal) or tostring(math.floor(m.Progress or 0)).." / "..tostring(m.Goal)
end
function View.Build(parent,pf,x,y,w,h,options)
 local state=options.State or {};local whole=options.Whole;local compact=w<650
 local root=make("ScrollingFrame","Progress",parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
  BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.Cyan,ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.new()})
 local cw=w-24;local gap=16
 local content=box(root,"Content",8,8,cw,1);content.BackgroundTransparency=1
 state.Scroll=state.Scroll or {}
 local draw;local drawing=false;local scrollKey
 root:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
  if scrollKey and not drawing then state.Scroll[scrollKey]=root.CanvasPosition.Y end
 end)
 draw=function()
  drawing=true
  content:ClearAllChildren();local yy=0
  label(content,"Title","Your Progress",0,yy,cw,40,compact and 27 or 34)
  yy=44;yy+=copy(content,"Subtitle","Build your record. Earn ranks, titles and permanent starting funds.",0,yy,cw,14,C.Muted)+8
  yy+=copy(content,"StartingBalance","Starting balance: "..whole(pf.StartingBalance or Config.StartingBalance).." · includes +"..whole(pf.StartingBonus or 0).." permanent bonus",0,yy,cw,16,C.Green)+12
  if pf.New or not pf.RankId then
   yy+=copy(content,"Loading","Loading your ranks and titles…",0,yy,cw,18,C.Muted)
   content.Size=UDim2.fromOffset(cw,yy);root.CanvasSize=UDim2.fromOffset(0,yy+16);drawing=false;return
  end
  local heroW=compact and cw or math.floor((cw-gap)*.48)
  local heroH=compact and 178 or 236
  local hero=card(content,"CurrentRank",0,yy,heroW,heroH,C.Purple)
  make("UIGradient","Glow",hero,{Color=ColorSequence.new(Color3.fromRGB(105,58,186),Color3.fromRGB(22,35,82)),Rotation=65})
  hero.BackgroundColor3=Color3.new(1,1,1)
  local badgeSize=compact and 64 or 88;local tx=badgeSize+28;local tw=heroW-tx-16
  local ry=16+copy(hero,"RankCaption","PERMANENT RANK "..tostring(pf.RankLevel).." / "..#Config.Ranks,16,16,heroW-32,12,C.Gold)+10
  Art.Create(hero,"RankBadge",pf.RankBadge,12,ry,badgeSize)
  ry+=copy(hero,"Rank",pf.Rank,tx,ry,tw,compact and 20 or 25)+6
  ry+=copy(hero,"TitleCaption",#(pf.Titles or {})>0 and "FEATURED TITLE"or "TITLE COLLECTION",tx,ry,tw,12,C.Muted)+2
  ry+=copy(hero,"EquippedTitle",pf.Title,tx,ry,tw,16)
  heroH=math.max(heroH,ry+(compact and 18 or 88))
  hero.Size=UDim2.fromOffset(heroW,heroH)
  if not compact then
   label(hero,"ResultsLabel","LIFETIME NET PROFIT",14,heroH-58,heroW-28,18,12,C.Muted)
   label(hero,"Results",options.Signed(pf.Earned or 0),14,heroH-37,heroW-28,28,23,C.Green)
  end
  local nx,ny,nw=compact and 0 or heroW+gap,compact and yy+heroH+gap or yy,compact and cw or cw-heroW-gap
  -- RankNext comes from FundedAccounts:View, using the same config as rank awards.
  local n=pf.RankNext;local rankName=n and n.Name or "Highest rank reached"
  local titleHeight=height(rankName,23,nw-98)
  local nextCard=card(content,"NextRank",nx,ny,nw,1,C.Gold)
  nextCard:SetAttribute("RankId",n and n.Id)
  label(nextCard,"Eyebrow",n and "NEXT RANK" or "ALL RANKS EARNED",14,12,nw-94,18,12,C.Gold)
  Art.Create(nextCard,"Badge",n and n.Badge or pf.RankBadge,nw-76,12,62)
  label(nextCard,"Rank",rankName,14,34,nw-98,titleHeight,23)
  local by=math.max(88,42+titleHeight)
  if n then
   by+=copy(nextCard,"Goal","Meet all three lifetime goals:",14,by,nw-28,14,C.Muted)+8
   for _,metric in ipairs({{"Trades",pf.Trades or 0,"Closed trades"},{"Wins",pf.Wins or 0,"Profitable trades"},{"Profit",pf.Earned or 0,"Lifetime net profit"}})do
    local key,current,caption=metric[1],metric[2],metric[3];local goal=n[key]
    local met=key=="Profit" and (goal==0 or current+1e-6>=goal)or current>=goal
    local value=key=="Profit" and whole(current).." / "..whole(goal)or tostring(current).." / "..tostring(goal)
    local captionText=(met and "✓ "or "")..caption
    local captionW=math.ceil(TextService:GetTextSize(captionText,typeSize(14),F,Vector2.new(10000,10000)).X)+8
    local valueW=math.ceil(TextService:GetTextSize(value,typeSize(14),F,Vector2.new(10000,10000)).X)+8
    local inline=captionW+valueW+12<=nw-32
    local requirement=label(nextCard,"Requirement"..key,captionText,16,by,inline and captionW or nw-32,height(captionText,14,nw-32),14,met and C.Green or C.Text)
    requirement:SetAttribute("Current",current);requirement:SetAttribute("Goal",goal);requirement:SetAttribute("Met",met)
    if inline then
     local counter=label(nextCard,"Amount"..key,value,nw-16-valueW,by,valueW,requirement.Size.Y.Offset,14,met and C.Green or C.Muted)
     counter.TextXAlignment=Enum.TextXAlignment.Right
     by+=requirement.Size.Y.Offset+5
    else
     by+=requirement.Size.Y.Offset
     by+=copy(nextCard,"Amount"..key,value,16,by,nw-32,14,met and C.Green or C.Muted)+5
    end
    bar(nextCard,"Track"..key,16,by,nw-32,met and 1 or goal==0 and 1 or current/goal)
    by+=23
   end
  else
   by+=copy(nextCard,"Complete","You have unlocked every rank. Your highest rank is yours to keep.",14,by,nw-28,15,C.Muted)+16
  end
  local nextH=math.max(by,not compact and heroH or 0)
  nextCard.Size=UDim2.fromOffset(nw,nextH)
  if not compact then
   hero.Size=UDim2.fromOffset(heroW,nextH)
   hero.ResultsLabel.Position=UDim2.fromOffset(14,nextH-58)
   hero.Results.Position=UDim2.fromOffset(14,nextH-37)
  end
  yy=ny+nextH+gap
  if pf.Failed and options.Restart then options.Restart(content,0,yy,cw,44);yy+=56 end
  local count=#(pf.Titles or {})
  if (state.EarnedCount and count>state.EarnedCount)or(state.RankId and state.RankId~=pf.RankId)then
   hero.Border.Thickness=4;TweenService:Create(hero.Border,TweenInfo.new(.65),{Thickness=1.5}):Play()
  end
  state.EarnedCount=count;state.RankId=pf.RankId
  -- Retire the old rank ladder, including remembered selections from earlier UI builds.
  local collection="Titles";state.Collection=collection
  yy+=copy(content,"CollectionTitle","Title collection",0,yy,cw,22)+8
  local explanation="Close trades, earn wins and build lifetime net profit. Each goal earns a title and a permanent starting-balance bonus."
  yy+=copy(content,"CollectionHelp",explanation,0,yy,cw,13,C.Muted)+10
  local cols=cw>=1000 and 3 or cw>=620 and 2 or 1
  local function tile(parent,m,px,py,tileW,fixedH,isNext)
   local earned=m.Earned
   local status=earned and "✓ EARNED"or isNext and "→ NEXT"or "◇ LOCKED"
   local title=m.Title
   local titleH=height(title,19,tileW-98)
   local description=m.Name.."\n+"..whole(m.StartingBonus or 0).." starting balance · permanent"
   local descH=height(description,14,tileW-28)
   local top=math.max(88,42+titleH);local tileH=fixedH or top+descH+72
   local tile=card(parent,m.Key or m.Id,px,py,tileW,tileH,earned and C.Green or isNext and C.Gold or C.Edge)
   tile:SetAttribute("Earned",earned==true);tile:SetAttribute("Next",isNext==true)
   local badge=Art.Create(tile,"Badge",m.Badge,10,13,64);hover(tile,badge)
   label(tile,"Status",status,84,10,tileW-98,20,12,earned and C.Green or isNext and C.Gold or C.Muted)
   label(tile,"Reward",title,84,34,tileW-98,titleH,19)
   label(tile,"Goal",description,14,top,tileW-28,descH,14,C.Muted)
   local by=top+descH+9
   bar(tile,"Track",14,by,tileW-28,earned and 1 or m.Progress/m.Goal)
   local value=earned and (m.EarlierGoal and "Kept from an earlier goal" or "Yours to keep")or amount(m,whole)
   label(tile,"Amount",value,14,by+13,tileW-28,height(value,14,tileW-28),14)
   return tileH
  end
  do
   local groups={
    {Kind="Trades",Name="Closed trades",Tab="Trades",Color=C.Cyan,Value=tostring(pf.Trades or 0).." closed"},
    {Kind="Wins",Name="Profitable trades",Tab="Wins",Color=C.Green,Value=tostring(pf.Wins or 0).." profitable"},
    {Kind="Profit",Name="Lifetime net profit",Tab="Profit",Color=C.Gold,Value=options.Signed(pf.Earned or 0)},
   }
   for _,g in ipairs(groups)do
    g.Items={};g.Earned=0
    for _,m in ipairs(pf.Milestones or {})do if m.Kind==g.Kind then table.insert(g.Items,m)end end
    table.sort(g.Items,function(a,b)return a.Goal==b.Goal and a.Key<b.Key or a.Goal<b.Goal end)
    for _,m in ipairs(g.Items)do if m.Earned then g.Earned+=1 elseif not g.Next then g.Next=m.Key end end
   end
   cols=cw>=840 and 3 or 1
   if cols==1 then
    state.Track=state.Track or "Trades"
    local tabW=(cw-2*gap)/3
    for i,g in ipairs(groups)do
     local b=make("TextButton","TrackTab"..g.Kind,content,{Text=g.Tab,Font=F,TextSize=typeSize(14),TextColor3=C.Text,
      Position=UDim2.fromOffset((i-1)*(tabW+gap),yy),Size=UDim2.fromOffset(tabW,36),BorderSizePixel=0,
      BackgroundColor3=state.Track==g.Kind and Color3.fromRGB(104,55,189)or C.Surface});round(b,10)
     b.Activated:Connect(function()state.Track=g.Kind;draw()end)
    end
    yy+=46
   end
   local tileW=(cw-(cols-1)*gap)/cols
   -- A shared height keeps rows aligned even when names or amounts wrap.
   local tileH=0
   for _,m in ipairs(pf.Milestones or {})do
    local top=math.max(88,42+height(m.Title,19,tileW-98))
    local value=m.Earned and (m.EarlierGoal and "Kept from an earlier goal"or "Yours to keep")or amount(m,whole)
    tileH=math.max(tileH,top+height(m.Name.."\n+"..whole(m.StartingBonus or 0).." starting balance · permanent",14,tileW-28)+22+height(value,14,tileW-28)+16)
   end
   local bottom=yy
   for i,g in ipairs(groups)do if cols==3 or state.Track==g.Kind then
    local gx=cols==3 and (i-1)*(tileW+gap)or 0
    local lane=box(content,"Column"..g.Kind,gx,yy,tileW,1);lane.BackgroundTransparency=1
    lane:SetAttribute("Kind",g.Kind);lane:SetAttribute("NextKey",g.Next)
    local header=card(lane,"Header",0,0,tileW,120,g.Color)
    local hy=12+copy(header,"Category",g.Name,16,12,tileW-32,18,g.Color)+4
    hy+=copy(header,"Total",g.Value,16,hy,tileW-32,18)+4
    hy+=copy(header,"Earned",g.Earned.." / "..#g.Items.." titles earned",16,hy,tileW-32,12,C.Muted)+12
    header.Size=UDim2.fromOffset(tileW,hy)
    local ly=hy+gap
    for _,m in ipairs(g.Items)do
     tile(lane,m,0,ly,tileW,tileH,g.Next==m.Key);ly+=tileH+gap
    end
    lane.Size=UDim2.fromOffset(tileW,ly-gap);bottom=math.max(bottom,yy+ly)
   end end
   yy=bottom+4
  end
  if collection=="Titles" and #(pf.Titles or {})>#(pf.Milestones or {}) then yy+=copy(content,"Alumni","Earlier achievements are preserved in your collection.",0,yy,cw,14,C.Muted)end
  -- Alumni titles have no obsolete account-tier labels; they remain permanent.
  if collection=="Titles" then
   local known={};for _,m in ipairs(pf.Milestones or {})do known[m.Title]=true end
   for _,title in ipairs(pf.Titles or {})do if not known[title]then yy+=copy(content,"AlumniTitle","✓ "..title.." · previously earned",0,yy,cw,15,C.Gold)+6 end end
  end
  content.Size=UDim2.fromOffset(cw,yy);root.CanvasSize=UDim2.fromOffset(0,yy+16)
  scrollKey=collection..(collection=="Titles"and cols==1 and (state.Track or "Trades")or "")
  root.CanvasPosition=Vector2.new(0,math.clamp(state.Scroll[scrollKey]or 0,0,math.max(0,yy+16-h)))
  drawing=false
  root:SetAttribute("Collection",collection);root:SetAttribute("Columns",cols)
 end
 draw();return root
end
return View
