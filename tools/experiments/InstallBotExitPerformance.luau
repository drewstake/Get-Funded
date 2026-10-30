-- Install only after validation. Refuse to overwrite edits made since the backup.
assert(not game:GetService('RunService'):IsRunning(),'Edit mode required')
local H=game:GetService('HttpService')
local Encoding=game:GetService('EncodingService')
local function hash(source)
 local bytes=Encoding:ComputeStringHash(source:gsub('\r\n','\n'),Enum.HashAlgorithm.Sha256)
 return(bytes:gsub('.',function(c)return string.format('%02x',string.byte(c))end))
end
local function resolve(path)
 local parts=string.split(path,'.');local parent=game
 for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),'Missing parent '..path)end
 return parent,parts[#parts],parent:FindFirstChild(parts[#parts])
end
local release=H:JSONDecode(H:GetAsync('http://127.0.0.1:8797/release'))
for path,item in pairs(release)do
 local _,_,instance=resolve(path)
 assert(hash(item.Source)==item.Hash,'Invalid source hash '..path)
 if item.ExpectedHash then
  assert(instance and instance.ClassName==item.ClassName,'Missing/wrong class '..path)
  assert(hash(instance.Source)==item.ExpectedHash,'Source changed since backup '..path)
 else assert(not instance,'New module already exists '..path)end
end
local installed={At=os.time(),Paths={}}
for path,item in pairs(release)do
 local parent,name,instance=resolve(path)
 if not instance then instance=Instance.new(item.ClassName);instance.Name=name;instance.Source=item.Source;instance.Parent=parent
 else instance.Source=item.Source end
 assert(hash(instance.Source)==item.Hash,'Installation verification failed '..path)
 installed.Paths[path]=item.Hash
end
H:PostAsync('http://127.0.0.1:8797/installed.json',H:JSONEncode(installed),Enum.HttpContentType.ApplicationJson)
