local H=game:GetService('HttpService')
local root=game.ServerScriptService.MarketReign
local record=game:GetService('DataStoreService'):GetDataStore('MarketReign_Continuous_v1','Studio'):GetAsync('primary-exchange')
local saved=require(root.WorldCheckpoint).Decode(record.Checkpoint)
local count,states,modes=0,0,{}
for _,a in ipairs(saved.Population.Agents)do if a.Kind=='Maker'then count+=1;if a.Maker then states+=1;modes[a.Maker.Mode]=(modes[a.Maker.Mode]or 0)+1 end end end
local result={Checkpoint=saved.Version,MakerPolicy=saved.Config.BotMaker.Version,MomentumPolicy=saved.Config.BotMomentum.Version,WhalePolicy=saved.Config.BotWhale.Version,NewsFrequency=saved.Config.NewsFrequency,MakerCount=count,MakerStates=states,Modes=modes,Step=saved.Engine.Step}
assert(result.Checkpoint==28 and result.MakerPolicy==1 and result.MomentumPolicy==1 and result.WhalePolicy==1 and result.NewsFrequency==0 and count==180)
H:PostAsync('http://127.0.0.1:8819/persisted-verification.json',H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
return result
