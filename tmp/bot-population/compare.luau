local fs=require('@lune/fs');local serde=require('@lune/serde');local process=require('@lune/process')
local X=require('../../tools/BotPopulationExperiment')
local variant=process.args[1]or 'proposed';local seed=tonumber(process.args[2])or 5501;local seconds=tonumber(process.args[3])or 21600
local directory=variant=='baseline'and './baseline/'or './proposed/'
local E=require(directory..'MarketEngine');local P=require(directory..'Participants');local C=require(directory..'MarketConfig');local CP=require(directory..'WorldCheckpoint')
local r=X.Run(E,P,C,CP,{Seed=seed,Seconds=seconds,Variant=variant,WithoutStrategyFixes=variant=='population_only',Progress=function(t)print(variant,seed,t)end})
local path='output/bot-population-20261014/'..variant..'-'..seed..'-'..seconds..'.json'
fs.writeFile(path,serde.encode('json',r,true));print('DONE',path)
