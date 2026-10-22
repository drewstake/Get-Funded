local fs=require('@lune/fs')
local serde=require('@lune/serde')
local luau=require('@lune/luau')
local process=require('@lune/process')
local roblox=require('@lune/roblox')
local decode=require('./ExactJson')
local base='output/momentum-20261021/'
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64encode(raw)
 local out={}
 for i=1,#raw,3 do
  local a,b,c=string.byte(raw,i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
  local x=math.floor(n/262144)%64;local y=math.floor(n/4096)%64;local z=math.floor(n/64)%64;local w=n%64
  out[#out+1]=alphabet:sub(x+1,x+1)..alphabet:sub(y+1,y+1)..(b and alphabet:sub(z+1,z+1)or '=')..(c and alphabet:sub(w+1,w+1)or '=')
 end
 return table.concat(out)
end
local lookup={};for i=1,#alphabet do lookup[string.byte(alphabet,i)]=i-1 end
local function b64decode(raw)
 local out={}
 for i=1,#raw,4 do
  local a,b,c,d=string.byte(raw,i,i+3);local n=lookup[a]*262144+lookup[b]*4096+(lookup[c]or 0)*64+(lookup[d]or 0)
  out[#out+1]=string.char(math.floor(n/65536)%256)..(c~=61 and string.char(math.floor(n/256)%256)or '')..(d~=61 and string.char(n%256)or '')
 end
 return table.concat(out)
end
local Http={}
function Http:JSONEncode(value)return serde.encode('json',value)end
function Http:JSONDecode(value)return decode(value)end
local Encoding={}
function Encoding:ComputeStringHash(raw)return (serde.hash('sha256',raw):gsub('%x%x',function(v)return string.char(tonumber(v,16))end))end
function Encoding:CompressBuffer(raw,_,level)return buffer.fromstring(serde.compress('zstd',buffer.tostring(raw),level))end
function Encoding:DecompressBuffer(raw)return buffer.fromstring(serde.decompress('zstd',buffer.tostring(raw)))end
function Encoding:GetDecompressedBufferSize(raw)return #serde.decompress('zstd',buffer.tostring(raw))end
function Encoding:Base64Encode(raw)return buffer.fromstring(b64encode(buffer.tostring(raw)))end
function Encoding:Base64Decode(raw)return buffer.fromstring(b64decode(buffer.tostring(raw)))end
local Enum={HashAlgorithm={Sha256='sha256'},CompressionAlgorithm={Zstd='zstd'}}
local task={wait=function()end}
local function build(arm)
 local root={Name=arm,Shared={}}
 for _,dir in ipairs({'server','shared'})do
  local folder=dir=='server'and root or root.Shared
  for _,file in ipairs(fs.readDir(base..'original/'..dir))do if file:sub(-5)=='.luau'then
   local name=file:sub(1,-6);local path=base..'original/'..dir..'/'..file
   if arm=='Candidate'and fs.isFile(base..'candidate/'..file)then path=base..'candidate/'..file end
   folder[name]={Name=name,Parent=folder,Source=fs.readFile(path)}
  end end
 end
 if arm=='Candidate'then for _,name in ipairs({'BotMomentum','BotMomentumTests'})do root[name]={Name=name,Parent=root,Source=fs.readFile(base..'candidate/'..name..'.luau')}end end
 local game={ReplicatedStorage={MarketReign=root.Shared},ServerScriptService={MarketReign=root}}
 function game:GetService(name)
  if name=='HttpService'then return Http elseif name=='EncodingService'then return Encoding end
  error('Unsupported service in offline lab: '..name)
 end
 local cache={}
 local function req(m)
  assert(type(m)=='table'and m.Source,'Invalid module')
  if cache[m]then return cache[m]end
  local code='return function(script,require,game,Enum,task,Color3,Vector3,Vector2,CFrame)\n'..m.Source..'\nend'
  local fn=luau.load(luau.compile(code,{optimizationLevel=2}),{debugName=arm..'.'..m.Name,codegenEnabled=true})()
  local result=fn(m,req,game,Enum,task,roblox.Color3,roblox.Vector3,roblox.Vector2,roblox.CFrame);cache[m]=result;return result
 end
 root.Require=req
 root.Http=Http;root.Game=game;root.Enum=Enum;root.Task=task
 return root
end
local function load(root,file)
 local fn=luau.load(luau.compile('return function(require,game,task)\n'..fs.readFile(base..file)..'\nend',{optimizationLevel=2}),{debugName=file,codegenEnabled=true})()
 return fn(root.Require,root.Game,root.Task)
end
local function snapshot(name)
 local path=base..'snapshots/normalized-'..name..'.json'
 return Http:JSONDecode(fs.readFile(path))
end
local mode=process.args[1]or 'parity'
local arm=process.args[2]or 'Candidate'
local name=process.args[3]or 'Seed71'
local root=build(arm);local req=root.Require;local CP=req(root.WorldCheckpoint);local c=req(root.Shared.MarketConfig)
if mode=='tests'then
 local results=req(root.BotMomentumTests).Run();fs.writeFile(base..'local-momentum-tests.json',Http:JSONEncode(results));print(Http:JSONEncode(results))
elseif mode=='parity'then
 local e,p=CP.Restore(snapshot(name),c)
 for _=1,400 do p:Step()end
 fs.writeFile(base..'parity-local-'..arm..'-'..name..'.json',Http:JSONEncode(CP.Capture(e,p)))
 print(Http:JSONEncode({Hash=e.TradeHash,Trades=e.NextTrade,Random=p.Random.State,Time=e.Time,Audit=e:Audit()}))
elseif mode=='seed'then
 local e=req(root.MarketEngine).new(c,tonumber(name));local p=req(root.Participants).new(e);local start=os.clock()
 while e.Time<1800 do p:Step()end
 fs.writeFile(base..'snapshots/normalized-Seed'..name..'.json',Http:JSONEncode(CP.Capture(e,p)))
 print('Prepared seed',name,os.clock()-start)
elseif mode=='benchmark'then
 local B=load(root,'MomentumBenchmark.luau');local lab={Results={}}
 local started=os.clock();local last=started
 root.Task.wait=function()
  if os.clock()-last>5 then fs.writeFile(base..'progress-'..arm..'-'..name..'.json',Http:JSONEncode(lab.Progress or {}));last=os.clock()end
 end
 local result=B.Run(root,snapshot(name),name,arm,lab)
 fs.writeFile(base..'results/'..name..'-'..arm..'.json',Http:JSONEncode(result))
 print('Complete',arm,name,os.clock()-started)
end
