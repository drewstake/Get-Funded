from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;W=R.parents[1]
BASE=R.parent/'diversity-20261022/original/shared'
mapping='''-- Visible chart tiers use existing stored series. Exchange time and candle history stay intact.
-- Keys are the server/checkpoint series IDs; labels are the player-facing chart tiers.
local T={
 Default="5m",
 Order=table.freeze({"5m","15m","1h","1D"}),
 Labels=table.freeze({["5m"]="1m",["15m"]="5m",["1h"]="15m",["1D"]="1h"}),
 Tooltips=table.freeze({["5m"]="1 minute",["15m"]="5 minutes",["1h"]="15 minutes",["1D"]="1 hour"}),
}
return table.freeze(T)
'''
def once(s,old,new):
 assert s.count(old)==1,(old,s.count(old));return s.replace(old,new)
def change(name,s):
 if name=='MarketClient.luau':
  s=once(s,'local Config=require(root.MarketConfig)','local Config=require(root.MarketConfig)\nlocal Timeframes=require(root.ChartTimeframes)')
  s=once(s,'Timeframe="1m",','Timeframe=Timeframes.Default,')
  s=once(s,'self:Subscribe(Config.ContractOrder[1],"1m")','self:Subscribe(Config.ContractOrder[1],Timeframes.Default)')
 elif name=='TerminalUI.luau':
  s=once(s,'local ChartView = require(script.Parent.ChartView)','local ChartView = require(script.Parent.ChartView)\nlocal Timeframes = require(script.Parent.ChartTimeframes)')
  s=once(s,'Timeframe="1m",','Timeframe=Timeframes.Default,')
  s=once(s,'local list={"1m","5m","15m","1h","1D"}','local list=Timeframes.Order')
  s=once(s,'option(p,"Choose"..tf,','option(p,"Choose"..Timeframes.Labels[tf],')
  s=once(s,'optionLabel(b,"Label",tf,','optionLabel(b,"Label",Timeframes.Labels[tf],')
 elif name=='ChartView.luau':
  s=once(s,'local Viewport=require(script.Parent.ChartViewport)','local Viewport=require(script.Parent.ChartViewport)\nlocal Timeframes=require(script.Parent.ChartTimeframes)')
  s=once(s,'local asset=TIMEFRAME_IMAGES[timeframe];','local asset=TIMEFRAME_IMAGES[Timeframes.Labels[timeframe]];')
  s=once(s,'local tfW=inline and math.clamp(math.floor((w-256)/5),34,54)or 0','local timeframeCount=#Timeframes.Order\n local tfW=inline and math.clamp(math.floor((w-256)/timeframeCount),34,54)or 0')
  s=once(s,'100+5*tfW+4','100+timeframeCount*tfW+4')
  s=once(s,'100,0,5*tfW,headH','100,0,timeframeCount*tfW,headH')
  s=once(s,'-- Twelve equally sized controls, plus padding and the three group gaps.','-- Visible timeframe choices plus seven drawing controls and the three group gaps.')
  s=once(s,'math.floor((w-52)/12)','math.floor((w-52)/(timeframeCount+7))')
  s=once(s,'for _,tf in ipairs({"1m","5m","15m","1h","1D"})do','for _,tf in ipairs(Timeframes.Order)do')
  s=once(s,'mobile and(w-16)/5','mobile and(w-16)/timeframeCount')
  s=once(s,'button(tb,"Time"..tf,','button(tb,"Time"..Timeframes.Labels[tf],')
  s=once(s,'b:SetAttribute("Tooltip",tf=="1D"and"1 day"or tf=="1h"and"1 hour"or tf:gsub("m", " minutes"))','b:SetAttribute("Tooltip",Timeframes.Tooltips[tf])\n  b:SetAttribute("CandleSeries",tf)')
 return s
for name in ['MarketClient.luau','TerminalUI.luau','ChartView.luau']:
 before=(BASE/name).read_text(encoding='utf8');after=change(name,before)
 for folder in ['original','candidate']:(R/folder).mkdir(exist_ok=True)
 (R/'original'/name).write_text(before,encoding='utf8');(R/'candidate'/name).write_text(after,encoding='utf8')
(R/'candidate/ChartTimeframes.luau').write_text(mapping,encoding='utf8')
manifest={p.name:hashlib.sha256(p.read_text(encoding='utf8').encode()).hexdigest()for p in (R/'candidate').glob('*.luau')}
(R/'manifest.json').write_text(json.dumps(manifest,indent=2))
patch=[]
for name in manifest:
 before=(R/'original'/name).read_text(encoding='utf8')if(R/'original'/name).exists()else''
 after=(R/'candidate'/name).read_text(encoding='utf8');patch.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='original/'+name,tofile='candidate/'+name))
(R/'change.patch').write_text(''.join(patch),encoding='utf8')
bundle={p.name:p.read_text(encoding='utf8')for p in BASE.glob('*.luau')}
bundle.update({p.name:p.read_text(encoding='utf8')for p in (R/'candidate').glob('*.luau')})
(R/'candidate-bundle.json').write_text(json.dumps(bundle),encoding='utf8')
(R/'expected-original.json').write_text(json.dumps({p.name:p.read_text(encoding='utf8')for p in (R/'original').glob('*.luau')}),encoding='utf8')
(R/'plan.json').write_text(json.dumps({'UserChoice':'Shift existing chart tiers','Mapping':{'1m':'5m','5m':'15m','15m':'1h','1h':'1D'},'DefaultVisible':'1m','DefaultSeries':'5m','RemovedVisible':'1D','StoredSeriesRemoved':[],
 'Clock':'Original simulated timestamps retained. This is the explicitly selected nonuniform tier shift, not 5:1 clock compression.',
 'Unchanged':['All server code','Order flow','Price data','Candle OHLCV and timestamps','Daily statistics','Checkpoint schema and history','ChartViewport seconds for canonical series'],
 'Validation':'Frozen candidate source; local compilation, native detached UI callbacks/layout at three sizes, independent historical candle/viewport tests, source readback before installation. No published changes.'},indent=2))
print('Frozen',len(manifest),'client presentation modules; no Studio or src edits')
