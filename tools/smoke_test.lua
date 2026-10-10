-- Smoke test: loads Lore against a minimal fake WoW API and renders every tab.
-- Run with any Lua 5.1+: lua tools/smoke_test.lua
unpack, time, date = unpack or table.unpack, os.time, os.date
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local function Obj()
    local o = { _shown = true, _w = 0, _scripts = {} }
    local special = {
        GetStringHeight = function() return 12 end,
        GetStringWidth = function() return 50 end,
        SetWidth = function(self, w) self._w = w end,
        SetSize = function(self, w) self._w = w end,
        GetWidth = function(self) return self._w end,
        SetHeight = function(self, h) self._h = h end,
        Show = function(self)  -- like the game, showing a hidden frame runs its OnShow
            local wasShown = self._shown
            self._shown = true
            if not wasShown and self._scripts.OnShow then self._scripts.OnShow(self) end
        end,
        Hide = function(self) self._shown = false end,
        SetShown = function(self, v) self._shown = v and true or false end,
        IsShown = function(self) return self._shown end,
        SetChecked = function(self, v) self._checked = v and true or false end,
        GetChecked = function(self) return self._checked end,
        SetScript = function(self, k, fn) self._scripts[k] = fn end,
        GetScript = function(self, k) return self._scripts[k] end,
        GetHighlightTexture = function() return Obj() end,
        GetCheckedTexture = function() return Obj() end,
        CreateTexture = function() return Obj() end,
        CreateFontString = function() return Obj() end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        StartMoving = function() end, StopMovingOrSizing = function() end,
        SetText = function(self, t) assert(t == nil or type(t) == "string" or type(t) == "number", "SetText got " .. type(t)); self._text = t end,
    }
    return setmetatable(o, { __index = function(_, k)
        if special[k] then return special[k] end
        return function() end
    end })
end
function CreateFrame(_, name) local f = Obj(); if name then _G[name] = f end; return f end
UIParent, DEFAULT_CHAT_FRAME, GameTooltip, Minimap = Obj(), Obj(), Obj(), Obj()
Minimap.GetWidth = function() return 140 end
Minimap.GetFrameLevel = function() return 2 end
Minimap.GetCenter = function() return 1000, 800 end
Minimap.GetEffectiveScale = function() return 1 end
GetCursorPosition = function() return 1000, 900 end  -- straight above the minimap's centre
math.atan2 = math.atan2 or math.atan                 -- WoW's Lua 5.1 has atan2
DEFAULT_CHAT_FRAME.AddMessage = function(_, m) print("[chat] " .. m) end
C_Timer = { After = function(_, fn) fn() end }
UnitFactionGroup = function() return "Horde" end
UnitLevel = function() return 9 end
UnitName = function() return "Grukk" end
UnitRace = function() return "Orc", "Orc", 2 end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitSex = function() return 2 end
GetRealZoneText = function() return "Durotar" end
LOG = { 823 }       -- Report to Orgnil: first quest of the Burning Blade story
local DONE = { [753] = true, [775] = true }  -- finished Rites of the Earthmother before Lore
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return DONE[id] or false end,
    GetNumQuestLogEntries = function() return #LOG + 1 end,
    GetInfo = function(i) if i == 1 then return { isHeader = true } end return { questID = LOG[i - 1], isHeader = false } end,
}
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList, UISpecialFrames, tinsert = {}, {}, table.insert
HOOKS = {}
function hooksecurefunc(a, b, c)  -- records hooks; the test calls them like Blizzard would
    if type(a) == "string" then HOOKS[a] = b else HOOKS[b] = c end
end

-- The map library needs the real game; a fake records which pins Lore places.
PINS = {}
HBD_PINS_WORLDMAP_SHOW_CURRENT, HBD_PINS_WORLDMAP_SHOW_PARENT = -1, 1
local fakePins = {
    AddWorldMapIconMap = function(_, ref, icon, map, x, y) PINS[#PINS + 1] = { kind = "world", map = map, x = x, y = y, info = icon.info } end,
    AddMinimapIconMap = function(_, ref, icon, map, x, y) PINS[#PINS + 1] = { kind = "minimap", map = map, x = x, y = y } end,
    RemoveAllWorldMapIcons = function() PINS = {} end,
    RemoveAllMinimapIcons = function() end,
}
LibStub = function() return fakePins end
WorldMapFrame = Obj()
WorldMapFrame.SetMapID = function(_, id) WorldMapFrame._map = id end

local root = (arg[0]:match("^(.*)/[^/]*$") or ".") .. "/../src/"
local function LoadAddon()
    local addon = {}
    for line in io.lines(root .. "Lore.toc") do
        if line:match("%.lua$") and not line:match("^Libs") then
            assert(loadfile(root .. line:gsub("\\", "/")))("Lore", addon)
        end
    end
    return addon
end
local ns = LoadAddon()

ns:ADDON_LOADED("Lore")
ns:PLAYER_LOGIN()
assert(ns.faction == "Horde" and ns.Theme.accentName == "Red", "a Horde character gets the Horde book")
print(("stories: %d total, %d for an orc warrior"):format(#ns.stories, #ns.myStories))

-- Build checks: required side quests are chapters, and eligibility covers every chapter.
for _, s in ipairs(ns.stories) do
    for _, q in ipairs(s.quests) do
        for _, id in ipairs(q.ids) do
            if id == 5742 then  -- Redemption needs Demon Dogs, Blood Tinged Skies, Carrion Grubbage
                for _, pre in ipairs({ 5542, 5543, 5544 }) do
                    assert(ns.questToStory[pre] == s, "In Dreams keeps Redemption's required quests")
                end
            end
        end
    end
    if s.id == "q1506" then
        assert(s.races and #s.races == 1 and s.races[1] == 2, "Creature of the Void is Orc-only")
    end
end
-- Journal entries are keyed by story ID and each quest maps to one story, so both are unique.
local seenStory, seenQuest = {}, {}
for _, s in ipairs(ns.stories) do
    assert(not seenStory[s.id], "duplicate story ID " .. s.id)
    seenStory[s.id] = true
    for _, q in ipairs(s.quests) do
        for _, id in ipairs(q.ids) do
            assert(not seenQuest[id], "quest " .. id .. " is in two stories")
            seenQuest[id] = true
        end
    end
end
-- IDs stay as they were before required quests were added (In Dreams kept q5543).
assert(ns.storiesById.q5543 and ns.storiesById.q5543.name == "In Dreams", "In Dreams keeps its ID")
assert(ns.storiesById.q3518 and ns.storiesById.q3561, "both Jediga payments keep their own IDs")
-- A required quest outside the story filters (3982 is a repeatable escort) still gets a chapter.
assert(ns.questToStory[3982] == ns.storiesById.q4001, "the Royal Rescue keeps its required escort")

local function Count() local n = 0 for _, p in ipairs(ns.UI.pools) do n = n + #p.used end return n end

SlashCmdList.LORE("")
assert(LoreFrame:IsShown(), "frame should be shown")
local story, progress = ns:GetCurrentStory()
print("current story:", story and story.name, progress and progress.activeIndex)
for _, key in ipairs({ "current", "browse", "journal", "settings" }) do
    ns.UI.SelectTab(key)
    print(("%-8s regions=%d height=%d"):format(key, Count(), rawget(ns.UI.content, "_h") or 0))
end
for _, e in ipairs(ns:GetJournalEntries()) do print("journal:", e.story.name, e.entry.preLore and "pre-Lore" or e.entry.completedAt) end
print("format:", ns:FormatQuestText("Hello $N the $C, $R.$B$BYou are a $gman:woman;."))
print("roman:", ns.UI.Roman(4), ns.UI.Roman(9), ns.UI.Roman(14), ns.UI.Roman(27), ns.UI.Roman(49))
ns.UI.SelectTab("journal"); SlashCmdList.LORE(""); SlashCmdList.LORE("")
assert(ns.UI.activeTab == "current", "should reopen on current")
LOG = {}
ns.UI.Refresh()
print("empty quest log renders:", Count(), "regions")
-- Pins: with an empty log there's no current tale, so suggestions get world-map pins.
ns:RefreshPins()
print("suggestion pins:", #PINS)
for _, p in ipairs(PINS) do assert(p.x > 0 and p.x <= 1 and p.y > 0 and p.y <= 1, "pin coords must be 0-1") end

-- Dark Storms (806) in the log, its first step done: the game marks Dark Storms itself, so
-- Lore pins only where the next chapter (Margoz) starts - on the world map and minimap.
LOG, DONE[823] = { 806 }, true
ns:RefreshPins()
for _, p in ipairs(PINS) do print("pin:", p.kind, p.map, p.x, p.y, p.info and (p.info.title .. " / " .. p.info.action)) end
assert(#PINS == 2, "one world + one minimap pin for the next chapter")
assert(PINS[1].info.title == "Margoz", "the pin is the next chapter, not the one in the log")

-- Show on the map: only adds a pin where the map has none. Dark Storms is in the log (the
-- game marks it) and Margoz already has a pin; the last chapter gets a new one.
local tale = ns:GetCurrentStory()
assert(ns:ShowOnMap(tale, 2) == "game" and #PINS == 2, "a chapter in the log gets no Lore pin")
assert(ns:ShowOnMap(tale, 3) == "pinned" and #PINS == 2, "the next chapter is already pinned")
assert(ns:ShowOnMap(tale, #tale.quests) == "marked" and #PINS == 4, "any other chapter gets a pin")
print("marked map:", WorldMapFrame._map, "pins now", #PINS)
SlashCmdList.LORE("pins")
assert(#PINS == 0, "pins off should clear them")
SlashCmdList.LORE("pins")
-- Minimap button: created at login, left-click toggles the book, drag moves it, /lore minimap hides it.
local button = LoreMinimapButton
assert(button, "minimap button should exist after login")
local wasShown = LoreFrame:IsShown()
button._scripts.OnClick(button, "LeftButton")
assert(LoreFrame:IsShown() ~= wasShown, "left-click toggles the book")
button._scripts.OnDragStart(button)
button._scripts.OnUpdate(button)
button._scripts.OnDragStop(button)
print("minimap angle after drag:", ns.db.settings.minimapAngle)
assert(math.abs(ns.db.settings.minimapAngle - 90) < 0.01, "dragging above the centre puts it at 90 degrees")
SlashCmdList.LORE("minimap")
assert(not button:IsShown(), "/lore minimap hides it")
SlashCmdList.LORE("minimap")
assert(button:IsShown(), "and shows it again")

-- Quest badges: a gossip list with a story quest (Dark Storms), a filler quest, and a plain
-- gossip option; only the story quest gets a badge.
local function QuestButton(data) local b = Obj(); b.GetElementData = function() return data end; return b end
local gossipButtons = {
    QuestButton({ availableQuestButton = true, info = { questID = 806, title = "Dark Storms" } }),
    QuestButton({ availableQuestButton = true, info = { questID = 999999, title = "Thinning the Boars" } }),
    QuestButton({ info = { name = "I'd like to train." } }),
}
GossipFrame = Obj()
GossipFrame.GreetingPanel = { ScrollBox = { ForEachFrame = function(_, fn) for _, b in ipairs(gossipButtons) do fn(b) end end } }
local onEvent = ns.UI.badgeEvents._scripts.OnEvent
onEvent(nil, "GOSSIP_SHOW")
assert(ns.UI.MarkGossip() == 1, "only the story quest in a gossip list gets a badge")
GossipFrame:Show()
SlashCmdList.LORE("badges")  -- off: a badge already drawn in an open list goes too
assert(not ns.UI.BadgeOn(gossipButtons[1]):IsShown(), "turning badges off clears an open gossip list")
SlashCmdList.LORE("badges")
assert(ns.UI.BadgeOn(gossipButtons[1]):IsShown(), "turning badges on marks it again")

-- Quest greeting without quest IDs: the title only counts when this NPC gives that chapter.
local darkStorms = tale.quests[2]
UnitName = function(unit) if unit == "npc" then return darkStorms.giver end return "Grukk" end
local greet = Obj(); greet.isActive = 0; greet.GetID = function() return 1 end; greet.GetText = function() return darkStorms.name end
QuestFrameGreetingPanel = Obj()
QuestFrameGreetingPanel.titleButtonPool = { EnumerateActive = function() local done; return function() if not done then done = true return greet end end end }
assert(ns.UI.MarkGreeting() == 1, "title match from the right NPC is badged")
UnitName = function(unit) if unit == "npc" then return "Some Peon" end return "Grukk" end
assert(ns.UI.MarkGreeting() == 0, "same title from another NPC is not")

-- The tag beside the quest window names the tale and chapter.
QuestFrame = Obj()
GetQuestID = function() return 806 end
onEvent(nil, "QUEST_DETAIL")
print("quest tag:", LoreQuestTag.story._text, "/", LoreQuestTag.chapter._text)
assert(LoreQuestTag:IsShown() and LoreQuestTag.chapter._text == "Chapter II of " .. ns.UI.Roman(#tale.quests))
GetQuestID = function() return 999999 end
onEvent(nil, "QUEST_DETAIL")
assert(not LoreQuestTag:IsShown(), "no tag on filler quests")
SlashCmdList.LORE("debug")  -- the diagnostic must not error

-- Chronicle: clicking a tale opens its page; "Show me where..." marks the map; back returns.
if not LoreFrame:IsShown() then SlashCmdList.LORE("") end
ns.UI.SelectTab("browse")
local clicked
for _, row in ipairs(ns.UI.rowPool.used) do
    if row._scripts.OnClick then clicked = row; break end
end
clicked._scripts.OnClick(clicked)
local preview = ns.storiesById[ns.UI.preview]
assert(ns.UI.activeTab == "browse" and preview, "clicking a Chronicle row opens the tale's page")
print("preview:", preview.name, Count(), "regions")
ns.UI.ShowStory(tale)  -- unfinished, with a chapter in the log
local where
for _, b in ipairs(ns.UI.buttonPool.used) do
    if (b._text or ""):match("^Show me where") then where = b end
end
assert(where, "an unfinished tale has a Show me where button")
WorldMapFrame._map = nil
where._scripts.OnClick(where)
assert(WorldMapFrame._map, "Show me where opens the map")
local back = ns.UI.rowPool.used[1]
back._scripts.OnClick(back)
assert(ns.UI.preview == nil, "back returns to the list")
-- A chapter that needs another tale's quest says so until that quest is done.
local needs
for _, s in ipairs(ns.stories) do
    for i, q in ipairs(s.quests) do
        if q.after then needs = needs or { story = s, index = i, quest = q } end
    end
end
assert(needs, "the data has chapters that wait on another tale")
local other, otherIndex = ns:GetChapter(needs.quest.after[1])
assert(other and other ~= needs.story, "the prerequisite belongs to another kept tale")
local function NeedsLine()
    for _, fs in ipairs(ns.UI.textPool.used) do
        if (fs._text or ""):match("^Needs ") then return fs._text end
    end
end
ns.marked = nil
ns.UI.ShowStory(needs.story)
ns.UI.ChapterList(ns.UI.NewLayout(300), needs.story, ns:GetStoryProgress(needs.story), needs.index)
print("prerequisite:", NeedsLine())
assert(NeedsLine() and NeedsLine():find(other.name, 1, true), "names the other tale")
DONE[needs.quest.after[1]] = true
ns.UI.Refresh()
ns.UI.ChapterList(ns.UI.NewLayout(300), needs.story, ns:GetStoryProgress(needs.story), needs.index)
assert(not NeedsLine(), "no line once the prerequisite is done")
DONE[needs.quest.after[1]] = nil
-- From the journal (a finished tale: no map button) and the bookmarks reset the page.
ns.UI.SelectTab("journal")
ns.UI.ShowStory(ns.storiesById[ns:GetJournalEntries()[1].story.id])
for _, b in ipairs(ns.UI.buttonPool.used) do
    assert(not (b._text or ""):match("^Show me where"), "finished tales have no map button")
end
ns.UI.SelectTab("browse")
assert(ns.UI.preview == nil, "the bookmark opens the list, not the last page")

-- Story messages: accepting a chapter, turning one in, a new tale, the end of a tale, and off.
local said
local addMessage = DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage = function(self, m) said = m; addMessage(self, m) end
local function Said(fn) said = nil; fn(); return said and said:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
assert(Said(function() ns:QUEST_TURNED_IN(806) end):find("Ak'Zeloth, chapter II of VII done. Next: Margoz, from Orgnil Soulscar.", 1, true))
LOG, DONE[806] = { 828 }, true
assert(Said(function() ns:QUEST_ACCEPTED(828) end):find("Ak'Zeloth, chapter III of VII: Margoz.", 1, true))
local fresh
for _, s in ipairs(ns.myStories) do
    if ns:GetStoryProgress(s).done == 0 and not ns:IsStoryComplete(s) then fresh = s; break end
end
assert(Said(function() ns:QUEST_ACCEPTED(0, fresh.quests[1].ids[1]) end):find("A new tale begins: " .. fresh.name, 1, true),
    "classic-style (index, questID) arguments work too")
local last = tale.quests[#tale.quests].ids[1]
assert(Said(function() ns:QUEST_TURNED_IN(last) end):find("Tale complete: Ak'Zeloth", 1, true))
assert(ns:GetJournalEntry(tale.id).completedAt, "the finished tale is in the journal")
assert(Said(function() ns:QUEST_TURNED_IN(999999) end) == nil, "filler quests say nothing")
SlashCmdList.LORE("messages")
assert(Said(function() ns:QUEST_ACCEPTED(fresh.quests[1].ids[1]) end) == nil, "/lore messages turns them off")
SlashCmdList.LORE("messages")

-- Settings: /lore settings opens the tab; each option is a checkbox that matches its setting
-- and its slash command; every command is listed; unknown input prints the same list.
LoreFrame:Hide()
SlashCmdList.LORE("settings")
assert(LoreFrame:IsShown() and ns.UI.activeTab == "settings", "/lore settings opens the Settings tab")
assert(#ns.UI.checkPool.used == #ns.options, "one checkbox per option")
local pinsBox = ns.UI.checkPool.used[1]
assert(pinsBox:GetChecked() == ns.db.settings.pins)
pinsBox:SetChecked(false); pinsBox._scripts.OnClick(pinsBox)
assert(ns.db.settings.pins == false and #PINS == 0, "unticking Map pins turns them off")
assert(ns.UI.checkPool.used[1]:GetChecked() == false, "the page redraws with the new state")
SlashCmdList.LORE("pins")
assert(ns.db.settings.pins and ns.UI.checkPool.used[1]:GetChecked(), "the slash command updates the open page")
local minimapBox = ns.UI.checkPool.used[2]
minimapBox:SetChecked(false); minimapBox._scripts.OnClick(minimapBox)
assert(not LoreMinimapButton:IsShown(), "unticking Minimap button hides it")
SlashCmdList.LORE("minimap")
assert(LoreMinimapButton:IsShown())
local helpLines = 0
DEFAULT_CHAT_FRAME.AddMessage = function(_, m) if m:find("/lore") then helpLines = helpLines + 1 end end
SlashCmdList.LORE("help")
assert(helpLines == #ns.commands and #ns.commands == 8, "help lists every command")
DEFAULT_CHAT_FRAME.AddMessage = addMessage

-- Quest log: Retail-style frames. A story title (Margoz, 828), a filler title, an objective
-- line (carries .questID, but isn't a button), a header, and a quest icon (an ID, no text).
-- Story titles get the tale in their tooltip; nothing is drawn on the quest log.
local function Row(kind, fields)
    local r = Obj()
    r.GetObjectType = function() return kind end
    for k, v in pairs(fields) do r[k] = v end
    return r
end
local logRows = {
    Row("Button", { questID = 828, Text = Obj() }),
    Row("Button", { questID = 999999, Text = Obj() }),
    Row("Frame", { questID = 828, Text = Obj() }),
    Row("Button", { Text = Obj() }),
    Row("Button", { questID = 828 }),
}
QuestScrollFrame = { Contents = Obj() }
QuestScrollFrame.Contents.GetChildren = function() return unpack(logRows) end
QuestLogQuests_Update = function() end
ns.UI.badgeEvents._scripts.OnEvent(nil, "ADDON_LOADED", "Blizzard_UIPanels_Game")
assert(HOOKS.QuestLogQuests_Update, "Lore hooks the quest log's redraw")
assert(HOOKS.QuestLogQuests_Update() == 1, "one story title in the quest log")
for _, row in ipairs(logRows) do assert(not ns.UI.BadgeOn(row), "nothing is drawn on the quest log") end
-- Recycled rows: the tooltip follows the quest.
logRows[1].questID, logRows[2].questID = 999999, 828
assert(HOOKS.QuestLogQuests_Update() == 1)
-- The Story badges option turns it off, and back on.
SlashCmdList.LORE("badges")
assert(not ns.db.settings.badges and ns.UI.MarkQuestLog() == 0, "/lore badges turns them off")
SlashCmdList.LORE("badges")
assert(ns.UI.MarkQuestLog() == 1, "and back on")
SlashCmdList.LORE("debug")

-- Alliance: a human paladin gets the Alliance tales, acts and blue book.
LoreCharDB, LoreFrame, LoreMinimapButton, LOG = nil, nil, nil, {}
UnitFactionGroup = function() return "Alliance" end
UnitRace = function() return "Human", "Human", 1 end
UnitClass = function() return "Paladin", "PALADIN", 2 end
GetRealZoneText = function() return "Elwynn Forest" end
ns = LoadAddon()
ns:ADDON_LOADED("Lore")
ns:PLAYER_LOGIN()
print(("alliance stories: %d total, %d for a human paladin"):format(#ns.stories, #ns.myStories))
assert(ns.faction == "Alliance" and ns.stories == ns.storyData.Alliance)
assert(ns.storiesById.q373 and ns.storiesById.q373.name == "The Unsent Letter", "the Defias plot is an Alliance tale")
assert(not ns.storiesById.q752, "no Horde tales (Rites of the Earthmother)")
assert(ns.acts[1].name == "Act I - Light and Valor", "Act I is the Alliance's")
assert(ns.Theme.colors.accent == ns.Theme.factions.Alliance.colors.accent, "the accent is Alliance blue")
assert(ns.Theme.textures.crest:find("Alliance"), "the crest is the Alliance's")
local tome
for _, s in ipairs(ns.myStories) do
    if s.name == "The Tome of Divinity" then tome = s end
    local paladin = not s.classes
    for _, c in ipairs(s.classes or {}) do paladin = paladin or c == 2 end
    assert(paladin, s.name .. " is open to paladins")
end
assert(tome, "a paladin gets their class tale")
-- Class quests list trainers of both factions; Alliance mages go to Bink in Ironforge.
assert(ns.questToStory[1947].quests[1].giver == "Bink", "class quests start at the faction's own trainer")
SlashCmdList.LORE("")
for _, key in ipairs({ "current", "browse", "journal", "settings" }) do
    ns.UI.SelectTab(key)
    print(("%-8s regions=%d"):format(key, Count()))
end
ns.UI.SelectTab("browse")
local title, key
for _, fs in ipairs(ns.UI.textPool.used) do
    if fs._text == "The Chronicle of the Alliance" then title = true end
    if (fs._text or ""):match("^Blue tales fit your level") then key = true end
end
assert(title and key, "the Chronicle names the Alliance and its blue tales")

-- A character of neither faction is told Lore doesn't support them, and nothing loads.
LoreCharDB, LoreFrame, LoreMinimapButton = nil, nil, nil
UnitFactionGroup = function() return nil end
ns = LoadAddon()
ns:ADDON_LOADED("Lore")
ns:PLAYER_LOGIN()
assert(ns.faction == nil and #ns.stories == 0 and not LoreMinimapButton, "nothing loads without a faction")
SlashCmdList.LORE("")
assert(not LoreFrame, "the book doesn't open")
print("SMOKE OK")
