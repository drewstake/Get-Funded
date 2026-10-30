-- Temporary Edit-only visual fixture, always replaced by RefreshStudioPreview before saving.
if _G.SummaryStatsPreview then _G.SummaryStatsPreview:Destroy() end
local shared=game.ReplicatedStorage.MarketReign:Clone() shared.Name="SummaryStatsPreviewModules" shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone() server.Name="SummaryStatsPreviewServer" server.MarketServer.Enabled=false server.Parent=game.ServerScriptService
local E=require(server.MarketEngine) local F=require(server.FundedAccounts) local S=require(server.TradeStats)
local C=require(shared.MarketConfig) local L=require(shared.ProgressionConfig)
local e=E.new(C,91) local f=F.new(e,L,C) f:Start("preview") f:Flag("preview","TutorialDone")
local a=e.Accounts[f:Owner("preview")]
local day=DateTime.fromUniversalTime(2026,9,27).UnixTimestamp
for i,v in ipairs({{750,day+1},{-225,day+2},{-50,day+86400},{0,day+172800}})do
 S.Add(a.Stats,{Pnl=v[1],ClosedAt=v[2],TradeId=i}) a.Realized+=v[1] a.Balance+=v[1] a.CompletedTrades=(a.CompletedTrades or 0)+1
end
local ctl=require(shared.TerminalUI).Mount(game.StarterGui.MarketReign,{Preview=true,StatsData=f:Stats("preview"),PortfolioData=f:View("preview")})
_G.SummaryStatsPreview=ctl
shared:Destroy() server:Destroy()
return "Temporary Stats visual fixture"
