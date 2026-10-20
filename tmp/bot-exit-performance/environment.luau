local serde=require('@lune/serde')
local task=require('@lune/task')
local Http={}
function Http:JSONEncode(x)return serde.encode('json',x)end
-- Lune's serde JSON decoder can lose one ULP on floats. Parse numeric tokens through
-- Luau tonumber so checkpoint replay tests exercise the original IEEE-754 values.
function Http:JSONDecode(s)
 local i=1;local value
 local function space()while s:sub(i,i):match('%s')do i+=1 end end
 local function str()
  local start=i;i+=1
  while i<=#s do local ch=s:sub(i,i);i+=1;if ch=='\\'then i+=1 elseif ch=='"'then return serde.decode('json',s:sub(start,i-1))end end
  error('Unterminated JSON string')
 end
 value=function()
  space();local ch=s:sub(i,i)
  if ch=='"'then return str()end
  if ch=='{'or ch=='['then
   i+=1;space();local out={};local closing=ch=='{'and '}'or ']'
   if s:sub(i,i)==closing then i+=1;return out end
   repeat
    space()
    if ch=='{'then local k=str();space();assert(s:sub(i,i)==':');i+=1;out[k]=value()else table.insert(out,value())end
    space();local ender=s:sub(i,i);i+=1;if ender==closing then return out end;assert(ender==',')
   until false
  end
  for literal,v in pairs({['true']=true,['false']=false})do if s:sub(i,i+#literal-1)==literal then i+=#literal;return v end end
  if s:sub(i,i+3)=='null'then i+=4;return nil end
  local token=s:sub(i):match('^[%+%-]?%d+%.?%d*[eE]?[%+%-]?%d*');assert(token,'Invalid JSON token');i+=#token;return assert(tonumber(token))
 end
 local out=value();space();assert(i>#s);return out
end
local guid=0
function Http:GenerateGUID()guid+=1;return string.format('%08x-0000-4000-8000-%012x',guid,guid)end
local Encoding={}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function Encoding:Base64Encode(x)
 local s=buffer.tostring(x);local out={}
 for i=1,#s,3 do
  local a,b,c=s:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
  for shift=18,0,-6 do local k=math.floor(n/2^shift)%64+1;table.insert(out,alphabet:sub(k,k))end
  if not c then out[#out]='='end;if not b then out[#out-1]='='end
 end
 return buffer.fromstring(table.concat(out))
end
function Encoding:Base64Decode(x)
 local s=buffer.tostring(x);local out={}
 for i=1,#s,4 do
  local n=0
  for j=0,3 do local ch=s:sub(i+j,i+j);n=n*64+(ch=='='and 0 or assert(alphabet:find(ch,1,true))-1)end
  table.insert(out,string.char(math.floor(n/65536)%256))
  if s:sub(i+2,i+2)~='='then table.insert(out,string.char(math.floor(n/256)%256))end
  if s:sub(i+3,i+3)~='='then table.insert(out,string.char(n%256))end
 end
 return buffer.fromstring(table.concat(out))
end
function Encoding:CompressBuffer(x)return buffer.fromstring(serde.compress('zstd',buffer.tostring(x)))end
function Encoding:DecompressBuffer(x)return buffer.fromstring(serde.decompress('zstd',buffer.tostring(x)))end
function Encoding:GetDecompressedBufferSize(x)return #serde.decompress('zstd',buffer.tostring(x))end
function Encoding:ComputeStringHash(x)
 local h=serde.hash('sha256',x)
 return (h:gsub('..',function(v)return string.char(tonumber(v,16))end))
end
local game={PlaceId=0,JobId='offline',PrivateServerId=''}
function game:GetService(name)
 if name=='HttpService'then return Http end
 if name=='EncodingService'then return Encoding end
 if name=='RunService'then return {IsStudio=function()return true end}end
 error('Offline harness forbids service '..name)
end
return {game=game,task=task,Enum={CompressionAlgorithm={Zstd='zstd'},HashAlgorithm={Sha256='sha256'}}}
