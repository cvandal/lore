-- Exports Questie's quest blacklist (quests that are in the data but not in the game)
-- as evaluated for Classic Era (vanilla).
--   lua5.1 tools/export_blacklist.lua tools/vendor/Questie tools/build/blacklist.json

local questieDir, outPath = assert(arg[1]), assert(arg[2])

local function permissive()
    return setmetatable({}, { __index = function() return false end })
end

local modules = {}
modules.Expansions = { Era = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1 }
modules.ContentPhases = permissive()
QuestieLoader = {
    CreateModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end,
    ImportModule = function(_, name) modules[name] = modules[name] or permissive(); return modules[name] end,
}
Questie = permissive()
Questie.Debug = function() end

dofile(questieDir .. "/Database/Corrections/QuestieQuestBlacklist.lua")
local list = modules.QuestieQuestBlacklist:Load()

local ids = {}
for id, value in pairs(list) do
    if value == true then ids[#ids + 1] = id end
end
table.sort(ids)

local file = assert(io.open(outPath, "w"))
file:write("[" .. table.concat(ids, ",") .. "]")
file:close()
io.stderr:write(("blacklist: %d quests -> %s\n"):format(#ids, outPath))
