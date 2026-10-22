-- Run in Edit only. Compare actual Source and editor buffers with the frozen export.
-- The HTTP bridge only reads local expected data and writes local audit evidence.
local H = game:GetService("HttpService")
local E = game:GetService("ScriptEditorService")
local expected = H:JSONDecode(H:GetAsync("http://127.0.0.1:8835/source-comparison-bundle.json"))
local roots = {
    server = game:GetService("ServerScriptService"):FindFirstChild("MarketReign"),
    shared = game:GetService("ReplicatedStorage"):FindFirstChild("MarketReign"),
}
local result = { Mode = "Edit", Modules = 0, AllSourceAndEditorMatch = true, Sources = {}, CheckedUTC = os.date("!%Y-%m-%dT%H:%M:%SZ") }
for scope, root in pairs(roots) do
    assert(root, "Missing source root: " .. scope)
    for _, m in ipairs(root:GetDescendants()) do
        if m:IsA("ModuleScript") then
            local key = scope .. "/" .. m.Name .. ".luau"
            local source = expected[key]
            local savedEqual = source ~= nil and m.Source:gsub("\r\n", "\n") == source
            local editorEqual = source ~= nil and E:GetEditorSource(m):gsub("\r\n", "\n") == source
            result.Modules += 1
            result.AllSourceAndEditorMatch = result.AllSourceAndEditorMatch and savedEqual and editorEqual
            table.insert(result.Sources, { File = key, MatchesOriginal = savedEqual, EditorMatchesOriginal = editorEqual })
            expected[key] = nil
        end
    end
    task.wait()
end
assert(next(expected) == nil, "Expected source missing from Studio")
assert(result.Modules == 105 and result.AllSourceAndEditorMatch, "Studio changed from frozen baseline")
table.sort(result.Sources, function(a, b) return a.File < b.File end)
H:PostAsync("http://127.0.0.1:8835/final-studio-readback.json", H:JSONEncode(result), Enum.HttpContentType.ApplicationJson)
return { Modules = result.Modules, AllSourceAndEditorMatch = result.AllSourceAndEditorMatch, Mode = result.Mode, CheckedUTC = result.CheckedUTC }
