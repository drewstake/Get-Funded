-- Executed through Studio against detached ModuleScripts and a read-only checkpoint.
local H=game:GetService('HttpService');local wasEnabled=H.HttpEnabled;H.HttpEnabled=true
local folder=Instance.new('Folder');folder.Name='DetachedLatencyBaseline';folder.Parent=game.ServerStorage
local raw=H:GetAsync('http://127.0.0.1:8818/bundle/baseline');local bundle=H:JSONDecode(raw)
local n=0;for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=folder;n+=1;if n%25==0 then task.wait()end end
local probe=Instance.new('ModuleScript');probe.Name='LatencyProbe';probe.Source=H:GetAsync('http://127.0.0.1:8818/script/probe.luau');probe.Parent=folder
local export=H:JSONDecode(H:GetAsync('http://127.0.0.1:8818/checkpoint'))
local CP=require(folder.WorldCheckpoint);local snapshot=CP.Decode(export.Checkpoint)
task.spawn(function()
 local ok,result=pcall(function()
  local report=require(probe).Run(function(name)return require(folder[name])end,snapshot,{Steps=2400,ProfileSteps=300,Scope='Native Studio detached saved world',Yield=function()task.wait()end,EncodeJSON=function(v)return H:JSONEncode(v)end})
  local e,p=CP.Restore(snapshot,require(folder.MarketConfig));local at=os.clock();local captured=CP.Capture(e,p);local capture=(os.clock()-at)*1000
  task.wait();at=os.clock();local json=H:JSONEncode(captured);local jsonMs=(os.clock()-at)*1000
  task.wait();local E=game:GetService('EncodingService');at=os.clock();local compressed=E:CompressBuffer(buffer.fromstring(json),Enum.CompressionAlgorithm.Zstd,3);local compress=(os.clock()-at)*1000
  task.wait();at=os.clock();E:ComputeStringHash(json,Enum.HashAlgorithm.Sha256);local hash=(os.clock()-at)*1000
  task.wait();at=os.clock();E:Base64Encode(compressed);local base64=(os.clock()-at)*1000
  report.Serialization={CaptureMs=capture,JSONMs=jsonMs,CompressMs=compress,HashMs=hash,Base64Ms=base64,Sections={}}
  for k,v in pairs(captured.Engine)do if type(v)=='table'then report.Serialization.Sections[k]=#H:JSONEncode(v);task.wait()end end
  H:PostAsync('http://127.0.0.1:8818/native-baseline.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
  return true
 end)
 folder:Destroy();H.HttpEnabled=wasEnabled
 if not ok then warn('Detached latency probe failed: '..tostring(result))end
end)
return {Started=true,Modules=n,Steps=2400,ProductionWrites=false}
