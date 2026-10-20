local fs=require('@lune/fs');local serde=require('@lune/serde');local env=require('./environment')
local saved=env.game:GetService('HttpService'):JSONDecode(fs.readFile('backups/execution-integrity-20261015/private-live-capture.json'))
local function profile(variant,CP,C)
 local e,p=CP.Restore(saved.Snapshot,C);e.ConnectedOwners=saved.ConnectedOwners
 local rows={};local stack={};local originals={}
 local function wrap(object,name,label)
  local original=object[name];if type(original)~='function'then return end
  table.insert(originals,{Object=object,Name=name,Original=original})
  local row={Calls=0,Ms=0,SelfMs=0,MaxMs=0};rows[label or name]=row
  object[name]=function(...)
   local start=os.clock();local frame={Child=0};table.insert(stack,frame)
   local result=table.pack(original(...));local ms=(os.clock()-start)*1000
   table.remove(stack);if #stack>0 then stack[#stack].Child+=ms end
   row.Calls+=1;row.Ms+=ms;row.SelfMs+=ms-frame.Child;row.MaxMs=math.max(row.MaxMs,ms)
   return table.unpack(result,1,result.n)
  end
 end
 for _,name in ipairs({'Submit','_match','Cancel','AmendOrder','AmendProtection','Summary','Exposure','OrderCapacity','_pruneBook','_cleanBook','_available','_rest','_unrest','_trade','_fillAccount','AdvanceClock','ProcessStops','ProcessPlayerOrders','Snapshot'})do wrap(e,name)end
 for _,name in ipairs({'Step','_maker','_reserve','_trader','_scalper','_fit','_repairRisk'})do wrap(p,name,'Bot.'..name)end
 local start=os.clock();local samples={};local n=e.NextOrder;local t=e.NextTrade
 for i=1,256 do local at=os.clock();p:Step();if i%6==0 then e:Snapshot('player:42875739:single:5','BX','1m',false)end;table.insert(samples,(os.clock()-at)*1000)end
 local total=(os.clock()-start)*1000;table.sort(samples)
 for _,entry in ipairs(originals)do entry.Object[entry.Name]=nil end
 local at=os.clock();local snapshot=CP.Capture(e,p);local capture=(os.clock()-at)*1000
 at=os.clock();local encoded=CP.Encode(snapshot);local encode=(os.clock()-at)*1000
 local result={Variant=variant,Steps=256,TotalMs=total,MeanMs=total/256,P95Ms=samples[math.ceil(#samples*.95)],MaxMs=samples[#samples],NewOrders=e.NextOrder-n,NewTrades=e.NextTrade-t,Scopes=rows,Persistence={CaptureMs=capture,EncodeMs=encode,RawBytes=encoded.RawBytes},Audit=e:Audit()}
 fs.writeFile('output/execution-integrity-20261015/profile-'..variant..'.json',serde.encode('json',result))
 print(variant,total,result.P95Ms,result.MaxMs)
 local sorted={};for name,row in pairs(rows)do row.Name=name;table.insert(sorted,row)end;table.sort(sorted,function(a,b)return a.SelfMs>b.SelfMs end)
 for i=1,math.min(12,#sorted)do print(serde.encode('json',sorted[i]))end
end
profile('candidate',require('./candidate/WorldCheckpoint'),require('./candidate/MarketConfig'))
