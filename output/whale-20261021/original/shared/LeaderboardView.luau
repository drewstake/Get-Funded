-- Balance standings: amounts are clamped only for presentation, never in the ledger.
local View={}
function View.Draw(ctx,x,y,w,h,mobile,client)
 local C=ctx.C;local compact=w<600;local pad=compact and 12 or 20;local iw=w-pad*2
 local p=ctx.frame(ctx.Canvas,"Leaderboard",x,y,w,h,C.Panel);ctx.round(p,16);ctx.stroke(p,C.Cyan).Thickness=2;p.ClipsDescendants=true
 ctx.tint(p,Color3.fromRGB(8,49,127),Color3.fromRGB(3,24,67))
 local function text(parent,name,value,xx,yy,ww,hh,size,color,font,align)
  local t=ctx.text(parent,name,value,xx,yy,ww,hh,size,color or C.Text,font or Enum.Font.FredokaOne,align)
  t.TextWrapped=false;t.TextTruncate=Enum.TextTruncate.AtEnd;return t
 end
 local art=Instance.new("ImageLabel");art.Name="LeaderboardArtwork";art.Image="rbxassetid://132495280701944";art.BackgroundTransparency=1
 art.Position=UDim2.fromOffset(pad,8);art.Size=UDim2.fromOffset(42,42);art.Parent=p
 text(p,"Title","Leaderboard",pad+50,8,iw-50,42,compact and 26 or 34)
 local top=58;local tabW=(iw-92)/2
 for i,tab in ipairs({"Global","Server"})do
  local b=ctx.button(p,"Tab"..tab,tab,pad+(i-1)*(tabW+6),top,tabW,38,function()client:Select(tab)end,C.Raised,C.Text,16)
  ctx.gloss(b,client.Tab==tab and "Purple"or "Navy")
 end
 local refresh=ctx.button(p,"Retry",client.Busy and "…"or "Refresh",w-pad-80,top,80,38,function()client:Fetch(true)end,C.Raised,C.Text,14);ctx.gloss(refresh,"Navy")
 local data=client.Data or {State="Loading",Rows={}};local own=data.Your
 local status=({Loading="Loading balances…",Empty="Close a trade to join.",Error="Unavailable · select Refresh",Stale="Earlier balances · refresh to update"})[data.State]
 text(p,"Status",status or (client.Tab=="Global"and "Top 100 · account balance"or "This server · account balance"),pad,102,iw,24,13,C.Muted,Enum.Font.GothamMedium)
 local list=Instance.new("ScrollingFrame");list.Name="Rows";list.Position=UDim2.fromOffset(pad,154)
 list.Size=UDim2.fromOffset(iw,math.max(32,h-164));list.BackgroundTransparency=1;list.BorderSizePixel=0;list.ScrollBarThickness=4;list.ScrollBarImageColor3=C.Cyan;list.Parent=p
 local rw=iw-8
 text(p,"PlacementHeader","#",pad+4,130,30,20,12,C.Muted,Enum.Font.GothamBold)
 text(p,"PlayerHeader","PLAYER",pad+40,130,iw*.45,20,12,C.Muted,Enum.Font.GothamBold)
 text(p,"BalanceHeader","BALANCE",pad+iw*.55,130,iw*.45-8,20,12,C.Muted,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
 local function row(r,name,yy,pinned)
  local mine=pinned or own and r.UserId==own.UserId;local rh=compact and 82 or 70
  local tile=ctx.frame(list,name,0,yy,rw,rh,mine and Color3.fromRGB(44,42,115)or Color3.fromRGB(4,29,76));ctx.round(tile,10)
  ctx.stroke(tile,mine and C.Cyan or Color3.fromRGB(31,75,137)).Thickness=mine and 2 or 1
  tile:SetAttribute("UserId",r.UserId);tile:SetAttribute("CurrentPlayer",mine==true);tile:SetAttribute("Cents",r.Cents)
  text(tile,"Placement",r.Rank and tostring(r.Rank)or "—",4,10,30,32,18,C.Text,nil,Enum.TextXAlignment.Center)
  local avatar=Instance.new("ImageLabel");avatar.Name="Avatar";avatar.BackgroundColor3=C.Raised;avatar.BorderSizePixel=0
  avatar.Image=string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",math.max(1,r.UserId or 1))
  avatar.Position=UDim2.fromOffset(40,12);avatar.Size=UDim2.fromOffset(38,38);avatar.Parent=tile;ctx.round(avatar,10)
  local moneyW=compact and rw-96 or math.min(230,rw*.35)
  text(tile,"PlayerName",r.DisplayName or r.Name or tostring(r.UserId),88,10,compact and rw-98 or rw-moneyW-106,26,compact and 17 or 20)
  if mine then text(tile,"YouMarker","YOU",8,rh-26,64,20,12,C.Cyan,Enum.Font.GothamBold)end
  local value=math.max(0,(r.Cents or 0)/100)
  local balance=text(tile,"Balance",ctx.money(value),compact and 88 or rw-moneyW-14,compact and 42 or 20,moneyW,28,compact and 18 or 22,C.Text,Enum.Font.RobotoMono,compact and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right)
  balance.TextTruncate=Enum.TextTruncate.None;balance.TextScaled=true
  local limit=Instance.new("UITextSizeConstraint");limit.MinTextSize=10;limit.MaxTextSize=compact and 18 or 22;limit.Parent=balance
  tile:SetAttribute("DisplayedBalance",value)
  return rh+8
 end
 local yy=0
 local listed=false;for _,r in ipairs(data.Rows or {})do if own and r.UserId==own.UserId then listed=true end end
 if own and not listed then yy+=row(own,"YourStanding",yy,true);yy+=6 end
 for _,r in ipairs(data.Rows or {})do yy+=row(r,own and r.UserId==own.UserId and "YourStanding"or "Player"..r.UserId,yy,false)end
 if #(data.Rows or {})==0 then text(list,"Empty",status or "No standings yet. Close a trade to join.",0,yy+12,rw,48,14,C.Muted,Enum.Font.GothamMedium).TextWrapped=true;yy+=72 end
 list.CanvasSize=UDim2.fromOffset(0,yy)
 p:SetAttribute("State",data.State);p:SetAttribute("Tab",client.Tab);p:SetAttribute("RowCount",#(data.Rows or {}));return p
end
return View
