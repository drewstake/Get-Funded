-- Reversible Edit-mode source install. No Play, save, publish or datastore operation.
assert(not game:GetService('RunService'):IsRunning(),'Install in Edit mode')
assert(game.PlaceId==137759823569682,'Release targets Get Funded!')
local H=game:GetService('HttpService');local Enc=game:GetService('EncodingService')
local base='http://127.0.0.1:8807/'
local release=H:JSONDecode(H:GetAsync(base..'release'))
local function hash(s)local b=Enc:ComputeStringHash(s:gsub('\r\n','\n'),Enum.HashAlgorithm.Sha256);return(b:gsub('.',function(c)return string.format('%02x',string.byte(c))end))end
local changes={}
for path,item in pairs(release)do
 local parts=string.split(path,'.');local parent=game
 for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),'Missing parent '..path)end
 local old=parent:FindFirstChild(parts[#parts])
 assert(hash(item.Source)==item.Hash,'Release content changed '..path)
 assert((not old and item.ExpectedHash==false)or(old and old.ClassName==item.ClassName and(hash(old.Source)==item.ExpectedHash or hash(old.Source)==item.Hash)),'Concurrent source change '..path)
 table.insert(changes,{Path=path,Parent=parent,Name=parts[#parts],Object=old,Previous=old and old.Source,Item=item})
end
table.sort(changes,function(a,b)return a.Path<b.Path end)
local history=game:GetService('ChangeHistoryService');history:SetWaypoint('Before order-driven market')
local ok,err=xpcall(function()
 for _,row in ipairs(changes)do
  row.Object=row.Object or Instance.new(row.Item.ClassName)
  row.Object.Name=row.Name;row.Object.Source=row.Item.Source;row.Object.Parent=row.Parent
  assert(hash(row.Object.Source)==row.Item.Hash,'Installed hash mismatch '..row.Path)
 end
end,debug.traceback)
if not ok then
 for _,row in ipairs(changes)do if row.Object then if row.Previous then row.Object.Source=row.Previous else row.Object:Destroy()end end end
 error(err)
end
history:SetWaypoint('Order-driven price discovery and observed-move banners')
local report={Installed={},Count=#changes,Published=false,Saved=false,DataStoreWrites=false}
for _,row in ipairs(changes)do report.Installed[row.Path]=row.Item.Hash end
H:PostAsync(base..'installed.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
return {Count=report.Count,Verified=true,Published=false,Saved=false}
