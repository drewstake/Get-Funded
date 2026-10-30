return function(mode)
 local old=game.StarterGui:FindFirstChild("UpgradeVisualPreview")
 if old then old.Cleanup:Invoke()end
 local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="UpgradeVisualShared";shared.Parent=game.ReplicatedStorage
 local gui=Instance.new("ScreenGui");gui.Name="UpgradeVisualPreview";gui.DisplayOrder=99;gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
 local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
 local candles={};for i=1,100 do local o=5800+math.sin(i*.1)*8;candles[i]={Time=i*60,Open=o,High=o+2,Low=o-2,Close=o+1,Volume=50}end
 local quotes,cache={},{};for _,key in ipairs(C.ContractOrder)do quotes[key]={Last=5800,Open=5800,Bid=5799.75,Ask=5800.25};for _,tf in ipairs(C.Timeframes)do cache[key..":"..tf[1]]=candles end end
 local pf={Active="preview",Started=true,RankId="Apprentice",Rank="Trading Apprentice",RankBadge=2,RankLevel=2,Tutorial="Done",StartingBalance=11250,StartingBonus=1250,
  Earned=27500,Trades=100,Wins=25,Titles={"Green Spark","Tape Reader"},Title="Tape Reader",Milestones={},Ranks={},Accounts={}}
 for _,m in ipairs(L.Milestones)do local r=table.clone(m);r.Key=m.Id;r.Earned=m.Id=="FirstWin"or m.Id=="Trades5";r.Progress=r.Earned and m.Goal or 0;table.insert(pf.Milestones,r);if not pf.Next and not r.Earned then pf.Next=r end end
 for i,m in ipairs(L.Ranks)do local r=table.clone(m);r.Earned=i<=2;table.insert(pf.Ranks,r)end
 if mode=="Away"then pf.AwaySummary={Id="preview:1",Seconds=3665,MarketSeconds=3000,Total=-275,Realized=-100,Unrealized=-25,RealizedChange=-250,CarriedIn=150,UnrealizedChange=-25,
  Coverage="Exits use actual exchange trades while the server runs. The market pauses when no server is running; no missing prices or outcomes are invented.",
  Rows={{Contract="BX",Direction=1,Quantity=5,Remaining=3,Realized=-100,RealizedChange=-250,UnrealizedChange=-25,Exits={{Reason="Stop loss",Quantity=2,Notional=11600,Change=-250,Realized=-100}}}}}end
 local own={UserId=123,Name="ChoronicleAngel",DisplayName="ChoronicleAngel",Cents=1125000,Rank=3,Eligible=true}
 local board={State="Ready",Your=own,Rows={{UserId=1,DisplayName="MarketMaven",Cents=8652750,Rank=1},{UserId=2,DisplayName="GoldenHour",Cents=2944500,Rank=2},own,{UserId=4,DisplayName="New Trader",Cents=-18000,Rank=4}}}
 local ctl=require(shared.TerminalUI).Mount(gui,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=6000,Step=1},PortfolioData=pf,LeaderboardData=board})
 ctl.State.Screen=(mode=="Away"or mode=="ResetAccount")and "Trade"or mode
 ctl.State.Overlay=(mode=="Away"or mode=="ResetAccount")and mode or nil;ctl.Chart.Ctx.refresh()
 local cleanup=Instance.new("BindableFunction");cleanup.Name="Cleanup";cleanup.Parent=gui
 cleanup.OnInvoke=function()ctl:Destroy();shared:Destroy();gui:Destroy()end
 return {Mode=mode}
end
