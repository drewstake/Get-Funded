-- Native timing and depth sampling with production history limits. No saved-world writes.
local H=game:GetService('HttpService');local base='http://127.0.0.1:8807/'
local function post(name,data)H:PostAsync(base..name,H:JSONEncode(data),Enum.HttpContentType.ApplicationJson)end
local function clone(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=clone(x)end;return t end
task.spawn(function()
 local root=Instance.new('Folder');local report={Runs={}}
 local ok,err=xpcall(function()
  local bundle=H:JSONDecode(H:GetAsync(base..'bundle'))
  for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root end
  local C=require(root.MarketConfig);local E=require(root.MarketEngine);local P=require(root.Participants);local CP=require(root.WorldCheckpoint)
  for _,run in ipairs({{Name='candidate',Seed=19381},{Name='candidate',Seed=68473}})do
   local c=clone(C)
   if run.Name=='baseline'then
    c.BotPopulation.Version=1
    c.BotPopulation.Counts={Maker=20,Liquidity=24,Momentum=12,Value=20,Reversion=12,Protective=8,Scalper=24,Whale=4,Reserve=6}
    c.MakersPerInstrument=20;c.ParticipantsPerInstrument=76;c.WhalesPerInstrument=4;c.ScalpersPerInstrument=24;c.Reserve.Count=6
   end
   local start=os.clock();local e=E.new(c,run.Seed);local p=P.new(e);run.CreationMs=(os.clock()-start)*1000
   run.Participants=#p.Agents;run.Markets={};run.StepTotalMs=0;local times={}
   for _,key in ipairs(c.ContractOrder)do run.Markets[key]={Samples=0,TwoSided=0,TopFiveBid=0,TopFiveAsk=0,SpreadTicks=0,Initial=e.Books[key].Last}end
   for i=1,14400 do
    local t=os.clock();p:Step();local ms=(os.clock()-t)*1000;times[i]=ms;run.StepTotalMs+=ms
    if i%40==0 then
     for key,m in pairs(run.Markets)do local b=e.Books[key];m.Samples+=1
      if b.Bids[1]and b.Asks[1]then m.TwoSided+=1;m.SpreadTicks+=b.Asks[1].Price-b.Bids[1].Price end
      for level=1,5 do m.TopFiveBid+=b.Bids[level]and b.Bids[level].Quantity or 0;m.TopFiveAsk+=b.Asks[level]and b.Asks[level].Quantity or 0 end
     end
    end
    if i%2400==0 then e:Audit();post('benchmark-release-progress.json',{Run=run.Name,Seed=run.Seed,Seconds=e.Time})end
    if i%20==0 then task.wait()end
   end
   table.sort(times);run.MeanStepMs=run.StepTotalMs/#times;run.P95StepMs=times[math.ceil(#times*.95)];run.MaxStepMs=times[#times]
   run.Depleted=0;run.LiquidityPaused=0
   for _,a in ipairs(p.Agents)do local equity=e:Summary(e.Accounts[a.Id]).Equity
    if equity<=0 then run.Depleted+=1 end
    if a.Kind=='Liquidity'and equity<=a.Budget*(1-c.BotLiquidity.MaxDrawdown)then run.LiquidityPaused+=1 end
   end
   for key,m in pairs(run.Markets)do m.TopFiveBid/=m.Samples;m.TopFiveAsk/=m.Samples;m.SpreadTicks/=math.max(1,m.TwoSided);m.TwoSidedFraction=m.TwoSided/m.Samples;m.Final=e.Books[key].Last end
   local t=os.clock();local encoded=CP.EncodeWorld(e,p);run.EncodeMs=(os.clock()-t)*1000
   run.RawBytes=encoded.RawBytes;run.PayloadBytes=#encoded.Payload
   run.StoredBytesWithHeadroom=#H:JSONEncode({Checkpoint=encoded,Owner=string.rep('x',100),LeaseUntil=os.time()+90,Step=e.Step})+4096
   assert(run.StoredBytesWithHeadroom<3600000 and run.RawBytes<CP.MaxDecodedBytes,'Checkpoint capacity exceeded')
   run.Seconds=e.Time;run.Trades=e.NextTrade;run.Volume=e.TotalVolume;run.Audit=e:Audit()
   table.insert(report.Runs,run);post('benchmark-release-interim.json',report);task.wait()
  end
 end,debug.traceback)
 root:Destroy();report.Success=ok;report.Error=not ok and tostring(err)or nil;post('benchmark-release.json',report)
end)
return 'Native depth and performance benchmark started'
