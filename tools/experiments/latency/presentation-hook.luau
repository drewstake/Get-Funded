-- Temporary Studio-only presentation bridge. No order submission or account edits.
local root=script.Parent
local Chart=require(game.ReplicatedStorage.MarketReign.ChartView)
local original=Chart.Paint;local current
assert(type(original)=='function')
Chart.Paint=function(self,...)
 current=self;Chart.Paint=original
 return original(self,...)
end
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local fields={'Contract','Timeframe','Type','Qty','Limit','StopOn','TargetOn','StopDollars','TargetDollars','Tool','Drawings','Magnet','Level2Expanded','SoundOn','SoundLevel','Calm','Tab'}
local hook=Instance.new('BindableFunction');hook.Name='LatencyPresentation';hook.Parent=root
hook.OnInvoke=function(command,value)
 if not current then return nil end
 if command=='Export'then
  local state={};for _,key in ipairs(fields)do state[key]=copy(current.S[key])end
  return {State=state,Views=copy(current.Views),ChartAttributes=current.Ctx.Root:GetAttributes()}
 elseif command=='Import'then
  current.Views=copy(value.Views)
  for _,key in ipairs(fields)do current.S[key]=copy(value.State[key])end
  current.Ctx.Session:Subscribe(current.S.Contract,current.S.Timeframe)
  current.Ctx.Root.UIDiagnostics:Invoke('Render');current.Dirty=true
  return true
 elseif command=='Cleanup'then
  hook:Destroy();script:Destroy();return true
 end
end
