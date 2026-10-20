local fs=require("@lune/fs")
local roblox=require("@lune/roblox")
local serde=require("@lune/serde")
local path="output/help-redesign-20261015/Get Funded - Help Redesign.rbxl"
local game=roblox.deserializePlace(fs.readFile(path))
local actual=game.ReplicatedStorage.MarketReign.TerminalUI.Source:gsub("\r\n","\n")
assert(actual==fs.readFile("src/TerminalUI.luau"):gsub("\r\n","\n"),"Saved source mismatch")
assert(not game.ReplicatedStorage:FindFirstChild("HelpRedesignValidation"),"Temporary modules persisted")
assert(not game.StarterGui:FindFirstChild("HelpRedesignPreview"),"Temporary preview persisted")
local report={SavedPlace=path,SourceMatches=true,TemporaryModulesRemoved=true}
fs.writeFile("output/help-redesign-20261015/saved-verification.json",serde.encode("json",report,true))
print("Saved place verified: exact source match, no temporary validation objects.")
