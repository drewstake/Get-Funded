-- Derived liquidity checks are shared by blocked bot exits. Actual fills still go
-- through Submit, including ownership, reduce-only, capacity and price safeguards.
local Policy=require(script.Parent.PlayerExecution)
local Retry={}
local function revision(book)return book.ExitLiquidityRevision or 0 end
local function liquidity(e,b,side)
 e.BotExitLiquidity=e.BotExitLiquidity or {}
 local key=b.Key..":"..side;local cached=e.BotExitLiquidity[key]
 if cached and cached.Step==e.Step and cached.Revision==revision(b) and cached.Eligibility==e.EligibilityRevision and cached.Fair==b.FairReference then return cached.Available end
 local available=false
 for _,level in ipairs(side==1 and b.Asks or b.Bids)do
  if not Policy.Allows(e,b,level.Price,side)then break end
  for _,o in ipairs(level.Orders)do
   local a=e.Accounts[o.Owner]
   if a and e:_available(o,true)>0 then available=true;break end
  end
  if available then break end
 end
 e.BotExitLiquidity[key]={Step=e.Step,Revision=revision(b),Eligibility=e.EligibilityRevision,Fair=b.FairReference,Available=available}
 return available
end
local function remember(e,b,p,attempted)
 local prior=p.BotExitRetry
 p.BotExitRetry={At=e.Time+(e.Config.BotExitRetrySeconds or 4),Revision=revision(b),Eligibility=e.EligibilityRevision,Fair=b.FairReference,
  Reason=p.Triggered,AttemptStep=attempted and e.Step or prior and prior.AttemptStep}
end
function Retry.Ready(e,a,key,p)
 if a.Player or p.Triggered=="Take profit"then return true end
 local b=e.Books[key];local last=p.BotExitRetry
 if last and last.Reason==p.Triggered then
  if last.AttemptStep==e.Step then return false end
  if e.Time<last.At and last.Revision==revision(b) and last.Eligibility==e.EligibilityRevision and last.Fair==b.FairReference then return false end
 end
 if not liquidity(e,b,-p.Direction)then remember(e,b,p,false);return false end
 return true
end
function Retry.Attempted(e,a,key,p)
 if not a.Player and p.Triggered~="Take profit"then remember(e,e.Books[key],p,true)end
end
return Retry

