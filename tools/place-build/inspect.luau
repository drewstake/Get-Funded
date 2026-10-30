-- Read/compile only. Never require game modules or start a simulation.
local fs = require('@lune/fs')
local roblox = require('@lune/roblox')
local serde = require('@lune/serde')
local luau = require('@lune/luau')
local args = require('@lune/process').args
local place = roblox.deserializePlace(fs.readFile(args[1]))
local report = {Scripts = {}, Containers = {}, Instances = #place:GetDescendants()}
for _,v in ipairs(place:GetDescendants()) do
 if v:IsA('LuaSourceContainer') then
  luau.compile(v.Source)
  local item = {Path = v:GetFullName(), Class = v.ClassName, Source = v.Source}
  if v:IsA('BaseScript') then
   item.Disabled = v.Disabled
   item.RunContext = tostring(v.RunContext)
  end
  table.insert(report.Scripts, item)
 end
end
for _,path in ipairs({'ReplicatedFirst', 'ReplicatedStorage.MarketReign', 'ServerScriptService.MarketReign', 'StarterGui.MarketReign', 'StarterPlayer.StarterPlayerScripts'}) do
 local v = place
 for name in path:gmatch('[^.]+') do
  local found = nil
  for _,child in ipairs(v:GetChildren()) do
   if child.Name == name then assert(not found, 'Ambiguous parent: '..path); found = child end
  end
  assert(found, 'Missing parent: '..path)
  v = found
 end
 report.Containers[path] = v.ClassName
end
local gui = place.StarterGui.MarketReign
report.Gui = {Enabled = gui.Enabled, ResetOnSpawn = gui.ResetOnSpawn, ScreenInsets = tostring(gui.ScreenInsets)}
fs.writeFile(args[2], serde.encode('json', report, true))
