-- Exports QuestieDB's corrected vanilla (Classic Era) data to JSON for build_stories.py.
-- Needs PUC Lua 5.1 (LuaJIT can't load the NPC file). Run from the QuestieDB checkout,
-- because its loaders use relative paths:
--   cd tools/vendor/QuestieDB && lua5.1 ../../export_questiedb.lua ../../build ../pfQuest/db/enUS/quests.lua

local outDir = assert(arg[1], "usage: luajit export_questiedb.lua <outDir>")

local config = dofile("src/config.lua")
local flavorLoader = dofile("generator/flavor.lua")
if io.open("src/corrections/manifest.lua") then
  config.correctionManifest = dofile("src/corrections/manifest.lua")
end

local flavor
for _, f in ipairs(config.flavors) do
  if f.name == "Vanilla" then flavor = f end
end
assert(flavor, "Vanilla flavor not found in QuestieDB config")

local loaded, stats = flavorLoader.load(flavor, { Quest = true, Npc = true, Object = true, Item = true })
io.stderr:write(("corrections applied: %s\n"):format(tostring(stats.applied)))

-- Minimal JSON: every table becomes an object keyed by its Lua keys, which keeps
-- QuestieDB's sparse field indexes intact.
local function encode(value, out)
  local t = type(value)
  if t == "nil" then
    out[#out + 1] = "null"
  elseif t == "boolean" then
    out[#out + 1] = tostring(value)
  elseif t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      out[#out + 1] = "null"
    elseif value == math.floor(value) and math.abs(value) < 2^53 then
      out[#out + 1] = string.format("%d", value)
    else
      out[#out + 1] = string.format("%.10g", value)
    end
  elseif t == "string" then
    out[#out + 1] = '"' .. value:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    out[#out + 1] = "{"
    local first = true
    for k, v in pairs(value) do
      if not first then out[#out + 1] = "," end
      first = false
      encode(tostring(k), out)
      out[#out + 1] = ":"
      encode(v, out)
    end
    out[#out + 1] = "}"
  else
    error("cannot encode " .. t)
  end
end

for name, entry in pairs(loaded) do
  local out = {}
  encode(entry.entities, out)
  local path = outDir .. "/vanilla_" .. name:lower() .. ".json"
  local file = assert(io.open(path, "w"))
  file:write(table.concat(out))
  file:close()
  local count = 0
  for _ in pairs(entry.entities) do count = count + 1 end
  io.stderr:write(("%s: %d entities -> %s\n"):format(name, count, path))
end

-- pfQuest's English quest text (T = title, O = objectives, D = description).
local pfQuestFile = arg[2]
if pfQuestFile then
  pfDB = { quests = {} }
  dofile(pfQuestFile)
  local out = {}
  encode(pfDB.quests.enUS, out)
  local path = outDir .. "/pfquest_text.json"
  local file = assert(io.open(path, "w"))
  file:write(table.concat(out))
  file:close()
  io.stderr:write("pfQuest text -> " .. path .. "\n")
end
