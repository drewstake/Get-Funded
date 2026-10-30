-- Temporary Script in the gameplay VM: observation-only wrappers, original calls unchanged.
local root=script.Parent;local W=require(root.WorldService);local L=require(root.WorldLease)
local originals={};local events={};local serial=0
local function stamp(name,phase,id)
 local label='ProfilerSave.'..name..'.'..phase..'.'..id
 debug.profilebegin(label);debug.profileend()
 table.insert(events,{Label=label,At=os.clock()})
end
local function wrap(object,name)
 local original=object[name];table.insert(originals,{Object=object,Name=name,Original=original})
 object[name]=function(self,...)
  serial+=1;local id=serial;stamp(name,'Begin',id)
  local results=table.pack(original(self,...));stamp(name,'End',id)
  return table.unpack(results,1,results.n)
 end
end
wrap(W,'_encode');wrap(L,'_put');wrap(L,'Commit')
local b=Instance.new('BindableFunction');b.Name='MicroProfilerSaveMarkers';b.Parent=root
b.OnInvoke=function(command)
 if command=='Cleanup'then for _,row in ipairs(originals)do row.Object[row.Name]=row.Original end;b:Destroy();script:Destroy();return events end
 return events
end
