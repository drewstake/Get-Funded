-- Run against cloned shared modules in Studio. Synthetic presentation data; no account requests.
-- Set script.Parent to the candidate MarketReign module folder, then require this module and call it.
return function()
 local shared=script.Parent
 local UI=require(shared.TerminalUI)
 local candles={}
 for i=1,720 do
  local open=5820+math.floor(math.sin(i*.17)*28)*.25
  local close=open+(i%7-3)*.25
  candles[i]={Time=i*60,Open=open,Close=close,High=math.max(open,close)+1,Low=math.min(open,close)-1,Volume=20+i%63}
 end
 local cache={};local quotes={}
 local Market=require(shared.MarketConfig)
 for _,key in ipairs(Market.ContractOrder)do
  quotes[key]={Last=5820,Open=5820,Bid=5819.75,Ask=5820.25,Spread=.5}
  for _,tf in ipairs(Market.Timeframes)do cache[key..":"..tf[1]]=candles end
 end
 local screen=Instance.new("ScreenGui");screen.Name="ChartPerformanceFixture";screen.Enabled=false
 screen.Parent=game.Players.LocalPlayer.PlayerGui
 local controller
 local ok,result=xpcall(function()
  controller=UI.Mount(screen,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=43200,Step=1}})
  local chart=controller.Chart
  assert(chart.Geometry,"Fixture chart did not mount")
  local p=controller.Root.Canvas.Chart
  local function paint()
   chart:Paint(p.Position.X.Offset,p.Position.Y.Offset,p.Size.X.Offset,p.Size.Y.Offset,false,false,true)
  end
  local function full()chart.Dirty=true;paint()end
  local state=chart.Geometry.State
  state.Bars=600;state.AutoY=false;state.Low=5805;state.High=5835
  full()
  local function hover(i)
   local g=chart.Geometry
   chart.Hover=g.Plot.AbsolutePosition+Vector2.new(g.Left+g.Width*(.1+.8*(i%180)/180),g.Top+g.Height*.45)
   chart.HoverDirty=true;paint()
  end
  for i=1,20 do hover(i)end
  local samples={};local before=chart.PaintCount
  local objectCount=#p:GetDescendants()
  local step=chart.Ctx.Session.Step
  for i=1,240 do
   local start=os.clock();hover(i);samples[i]=(os.clock()-start)*1000
  end
  table.sort(samples)
  local total=0 for _,v in ipairs(samples)do total+=v end
  local report={Hover={MeanMs=total/#samples,MedianMs=samples[120],P95Ms=samples[228],MaxMs=samples[240],
   Samples=#samples,FullPaints=chart.PaintCount-before,NewObjects=#p:GetDescendants()-objectCount},
   VisibleCandles=#chart.Geometry.Data,Checks={}}
  local function check(name,passed)assert(passed,name);table.insert(report.Checks,name)end
  local g=chart.Geometry
  local crossTime=controller.Root:GetAttribute("CrosshairTime")
  check("Crosshair reports cursor time",crossTime~=nil)
  local cross=g.Plot.CrossV
  local hoverX=chart:Local(chart.Hover)
  check("Crosshair follows pointer",cross.Position.X.Offset==g.Left+math.floor(hoverX+.5))
  local candle
  local nearest=math.huge
  for _,d in ipairs(g.Data)do local delta=math.abs(d.Time-crossTime);if delta<nearest then candle=d;nearest=delta end end
  check("OHLC matches hovered candle",g.Plot.OHLC.Text:find(require(shared.MarketClient).Number(candle.Close),1,true)~=nil)
  -- A market update must take precedence over a queued hover paint.
  local tail=candles[#candles];tail.Close=tail.Open+1;tail.High=math.max(tail.High,tail.Close)
  before=chart.PaintCount;chart:OnMarketUpdate();hover(80)
  check("Market update forces a full paint",chart.PaintCount==before+1)
  state.Right-=60*8;chart.Dirty=true;before=chart.PaintCount;hover(81)
  check("Navigation forces a full paint",chart.PaintCount==before+1)
  -- Hover-only previews and magnet use the same geometry as full rendering.
  chart.Ctx.Options.Preview=false
  chart.S.Tool="Rect";chart.S.Magnet=true
  g=chart.Geometry;local target=g.Data[math.floor(#g.Data/2)]
  chart.Hover=g.Plot.AbsolutePosition+Vector2.new(g.Left+g.X(target.Time),g.Top+g.Y(target.High))
  chart.HoverDirty=true;paint()
  check("Magnet updates on pointer paint",chart.SnapShown~=nil)
  chart.Placement={Kind="Rect",A={Time=target.Time-120,Price=target.Low},B={Time=target.Time,Price=target.High},Waiting=true}
  chart.HoverDirty=true;paint()
  check("Rectangle preview updates on pointer paint",g.Plot.PriceLayer.DrawingLayer:FindFirstChild("Rect")~=nil)
  chart.Placement=nil;chart.S.Tool="Pan";chart.S.Magnet=false;chart.Hover=nil;chart.HoverDirty=true;paint()
  check("Crosshair hides on pointer exit",not g.Plot.CrossV.Visible)
  check("Rectangle preview hides on cancellation",not g.Plot.PriceLayer.DrawingLayer.Rect.Visible)
  check("Presentation leaves market step unchanged",chart.Ctx.Session.Step==step)
  check("No completed candle mutations",chart.Mutations==0)
  check("No candle color mismatches",chart.ColorMismatches==0)
  report.CandleCount=#candles
  return report
 end,debug.traceback)
 if controller then controller:Destroy()end
 screen:Destroy()
 if not ok then error(result)end
 return result
end
