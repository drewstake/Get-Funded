-- Shared presentation/state rules. Retry timing and admission decisions remain server-owned.
local Status={}
function Status.Apply(session,packet)
 session.CanTrade=packet.CanTrade==true and not packet.StatusOnly
 session.ConnectionStatus=packet.ConnectionStatus;session.ConnectionInfo=packet.ConnectionInfo
 session.PersistenceMode=packet.PersistenceMode
 if packet.NoAccount then
  session.Ready=false;session.AccountKey=nil;session.AccountToken=nil;session.RequestSession=nil
  session.Positions={};session.Orders={};session.History={};session.Fills={};session.Portfolio=nil
  session.Capacity=nil;session.Pending={};session.PreferencesPending=nil
  session.SummaryData={Balance=0,Equity=0,Unrealized=0,Session=0,Allowance=0,Count=0,Margin=0}
 else session.RequestSession=packet.RequestSession or session.RequestSession end
 session.NextId=math.max(session.NextId or 0,packet.RequestHigh or 0)
end
function Status.View(info,fallback)
 info=info or {}
 local after=math.max(0,math.ceil(info.RetryAfter or 0))
 return {Title=info.Title or "Connecting to your trading account",Message=info.Message or fallback or "Waiting for the shared exchange.",
  Detail=info.Detail or "Your saved progress stays on the shared exchange.",
  Button=after>0 and ((info.AutoRetry and "Checking again in "or "Retry in ")..after.."s")or info.CanRetry and "Retry connection"or "Please wait…",
  Enabled=info.CanRetry==true and after==0,Attention=info.Attention==true}
end
function Status.Layout(width,height)
 local content=math.max(height,344)
 return {Width=math.min(560,math.max(1,width-32)),X=math.max(16,(width-560)/2),Top=(content-328)/2,
  ContentHeight=content,MessageSize=width<500 and 15 or 17,TitleSize=width<500 and 20 or 25}
end
return Status
