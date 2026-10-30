-- Fail closed: a successful call without explicit, nonempty test results is not a pass.
local Report={}
local function array(rows)
 assert(type(rows)=="table" and #rows>0,"Test results must be a nonempty array")
 local count=0
 for key,row in pairs(rows)do
  count+=1;assert(type(key)=="number"and key%1==0 and key>=1 and key<=#rows,"Invalid result index")
  assert(type(row)=="table"and type(row.Name)=="string"and #row.Name>0 and type(row.Passed)=="boolean","Test row needs a name and explicit boolean Passed")
 end
 assert(count==#rows,"Sparse test results")
 return rows
end
function Report.Rows(result)
 assert(type(result)=="table","Suite must return explicit test results")
 if result.Results~=nil then
  local rows=array(result.Results);local passed=0;for _,r in ipairs(rows)do if r.Passed then passed+=1 end end
  assert(result.Total==#rows and result.Passed==passed,"Suite summary disagrees with its results")
  return rows
 elseif result.Cases~=nil then
  assert(type(result.Passed)=="boolean"and type(result.Cases)=="number"and result.Cases>0 and result.Cases<math.huge and result.Cases%1==0,"Invalid assertion summary")
  return {{Name="Assertions",Passed=result.Passed,Count=result.Cases}}
 end
 return array(result)
end
return Report
