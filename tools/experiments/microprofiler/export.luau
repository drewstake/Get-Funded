local storage=game.ServerStorage.MicroProfilerEvidence;local H=game.HttpService;local E=game:GetService('EncodingService')
local was=H.HttpEnabled;H.HttpEnabled=true
local ok,result=pcall(function()
 local reports={};for i=1,__COUNT__ do
  local raw=storage:Invoke('Buffer',i);local compressed=E:CompressBuffer(raw,Enum.CompressionAlgorithm.Zstd,3)
  local text=buffer.tostring(E:Base64Encode(compressed));local parts=math.ceil(#text/650000)
  for j=1,parts do
   H:PostAsync('http://127.0.0.1:8820/__PREFIX__-'..i..'-part-'..j..'.json',H:JSONEncode({Data=text:sub((j-1)*650000+1,j*650000)}),Enum.HttpContentType.ApplicationJson);task.wait()
  end
  local metadata={Codec='zstd-base64',Bytes=buffer.len(raw),Parts=parts,StoredBytes=buffer.len(compressed)}
  H:PostAsync('http://127.0.0.1:8820/__PREFIX__-'..i..'-info.json',H:JSONEncode(metadata),Enum.HttpContentType.ApplicationJson);table.insert(reports,metadata)
 end
 return reports
end);H.HttpEnabled=was;assert(ok,result);return result
