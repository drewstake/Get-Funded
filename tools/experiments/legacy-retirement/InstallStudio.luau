assert(not game:GetService('RunService'):IsRunning(),'Edit mode required')
local H=game:GetService('HttpService');local Encoding=game:GetService('EncodingService')
local function hash(source)
 local bytes=Encoding:ComputeStringHash(source:gsub('\r\n','\n'),Enum.HashAlgorithm.Sha256)
 return(bytes:gsub('.',function(c)return string.format('%02x',string.byte(c))end))
end
local function resolve(path)
 local parts=string.split(path,'.');local parent=game
 for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),'Missing parent '..path)end
 return parent,parts[#parts],parent:FindFirstChild(parts[#parts])
end
local release=H:JSONDecode(H:GetAsync('http://127.0.0.1:8796/release'))
for path,item in pairs(release)do
 local _,_,instance=resolve(path)
 assert(hash(item.Source)==item.Hash,'Invalid source hash '..path)
 if item.ExpectedHash then
  assert(instance and instance.ClassName==item.ClassName,'Missing/wrong class '..path)
  assert(hash(instance.Source)==item.ExpectedHash,'Source changed since backup '..path)
 else assert(not instance,'New module already exists '..path)end
end
local history=game:GetService('ChangeHistoryService');history:SetWaypoint('Before legacy market retirement')
local rollback={};local installed={At=os.time(),PlaceId=game.PlaceId,Paths={}}
local ok,err=pcall(function()
 for path,item in pairs(release)do
  local parent,name,instance=resolve(path)
  if not instance then
   instance=Instance.new(item.ClassName);instance.Name=name;table.insert(rollback,{Instance=instance,New=true})
   instance.Source=item.Source;instance.Parent=parent
  else table.insert(rollback,{Instance=instance,Source=instance.Source});instance.Source=item.Source end
  assert(hash(instance.Source)==item.Hash,'Installation verification failed '..path)
  installed.Paths[path]=item.Hash
 end
end)
if not ok then
 for _,row in ipairs(rollback)do if row.New then row.Instance:Destroy()else row.Instance.Source=row.Source end end
 error(err)
end
history:SetWaypoint('Legacy markets settled and archived; only BX BT BG active')
H:PostAsync('http://127.0.0.1:8796/installed.json',H:JSONEncode(installed),Enum.HttpContentType.ApplicationJson)
return installed
