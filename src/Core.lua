local ADDON_NAME, Lore = ...
_G.Lore = Lore

Lore.version = "0.1.0"

local defaults = {
    journal = {},   -- [storyId] = { completedAt, level, zone } or { preLore = true }
    settings = {
        point = nil,
        pins = true,    -- map pins for the current tale and suggestions
        minimapAngle = 200,  -- minimap button position, degrees around the rim
        minimapHidden = false,
        messages = true,     -- chat messages when a tale begins, moves on or ends
        badges = true,       -- mark story quests in NPC lists, the quest window and quest log tooltips
    },
}

local function ApplyDefaults(db, source)
    for key, value in pairs(source) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = {}
                ApplyDefaults(db[key], value)
            else
                db[key] = value
            end
        elseif type(value) == "table" and type(db[key]) == "table" then
            ApplyDefaults(db[key], value)
        end
    end
end

function Lore:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4a017Lore:|r " .. tostring(msg))
end

-- Events -------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_ACCEPTED")
events:SetScript("OnEvent", function(_, event, ...)
    if Lore[event] then
        Lore[event](Lore, ...)
    end
end)

function Lore:ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    LoreCharDB = LoreCharDB or {}
    ApplyDefaults(LoreCharDB, defaults)
    self.db = LoreCharDB
    events:UnregisterEvent("ADDON_LOADED")
end

function Lore:PLAYER_LOGIN()
    self.isHorde = UnitFactionGroup("player") == "Horde"
    if not self.isHorde then
        self:Print("Lore only supports Horde characters.")
        return
    end
    self:BuildMyStories()
    self.UI.CreateMinimapButton()
    -- Give the client a moment to load quest completion flags.
    C_Timer.After(3, function()
        Lore:RecordPreLoreCompletions()
        Lore:RefreshPins()
    end)
end

function Lore:QUEST_LOG_UPDATE()
    self:RequestRefresh()
end

-- Classic clients pass (questLogIndex, questID); WoW Forever passes just the questID.
function Lore:QUEST_ACCEPTED(first, second)
    if not self.isHorde then return end
    self:OnQuestAccepted(second or first)
    self:RequestRefresh()
end

function Lore:QUEST_TURNED_IN(questID)
    if not self.isHorde then return end
    self:OnQuestTurnedIn(questID)
    self:RequestRefresh()
end

-- Coalesce bursts of quest log events into a single redraw of the book and the pins.
local refreshPending = false
function Lore:RequestRefresh()
    if refreshPending or not self.isHorde then return end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = false
        Lore.UI.Refresh()
        Lore:RefreshPins()
    end)
end

-- Slash commands -------------------------------------------------------------

function Lore:Toggle()
    if not self.isHorde then
        self:Print("Lore only supports Horde characters.")
        return
    end
    self.UI.Toggle()
end

-- Options: settings the player turns on or off, from the Settings tab or a slash command.
-- Commands: everything /lore understands. Both lists drive the Settings tab and /lore help.
local settings = function() return Lore.db.settings end

Lore.options = {
    {
        command = "pins",
        label = "Map pins",
        description = "Pins on the world map and minimap for your tale's next chapter, or for tales to start when you're between tales.",
        get = function() return settings().pins end,
        set = function(on)
            settings().pins = on
            Lore:RefreshPins()
        end,
    },
    {
        command = "minimap",
        label = "Minimap button",
        description = "The Lore button on the minimap's edge. Click to open the book, right-click for map pins, drag to move.",
        get = function() return not settings().minimapHidden end,
        set = function(on)
            settings().minimapHidden = not on
            Lore.UI.UpdateMinimapButton()
        end,
    },
    {
        command = "badges",
        label = "Story badges",
        description = "A small Lore icon on story quests in an NPC's quest list, a tag beside the quest window, and the tale in your quest log's tooltips.",
        get = function() return settings().badges end,
        set = function(on)
            settings().badges = on
            Lore.UI.MarkGossip()
            Lore.UI.MarkGreeting()
            Lore.UI.MarkQuestLog()
            Lore.UI.UpdateQuestTag()
        end,
    },
    {
        command = "messages",
        label = "Story messages",
        description = "A line in chat when a tale begins, when you pick up or finish a chapter, and when a tale ends.",
        get = function() return settings().messages end,
        set = function(on) settings().messages = on end,
    },
}

function Lore:SetOption(option, on)
    option.set(on)
    self.UI.Refresh()
end

Lore.commands = {
    { command = "", description = "Open or close the book.", run = function() Lore:Toggle() end },
    { command = "settings", description = "Open the book on this Settings page.", run = function() Lore.UI.ShowTab("settings") end },
    -- The options' commands go here, built from Lore.options below.
    { command = "debug", description = "Report which quests Lore sees in an open NPC window and your quest log. Handy for bug reports.",
        run = function() Lore.UI.DebugBadges() end },
    { command = "reset", description = "Move the book back to the middle of the screen.",
        run = function()
            Lore.db.settings.point = nil
            Lore.UI.ResetPosition()
            Lore:Print("Window position reset.")
        end },
}

for i, option in ipairs(Lore.options) do
    table.insert(Lore.commands, 2 + i, {
        command = option.command,
        description = "Turn " .. option.label:lower() .. " on or off.",
        run = function()
            Lore:SetOption(option, not option.get())
            Lore:Print(option.label .. (option.get() and " on." or " off."))
        end,
    })
end

SLASH_LORE1 = "/lore"
SlashCmdList.LORE = function(input)
    local cmd = strtrim(input or ""):lower()
    for _, command in ipairs(Lore.commands) do
        if command.command == cmd then
            command.run()
            return
        end
    end
    for _, command in ipairs(Lore.commands) do
        Lore:Print(strtrim("/lore " .. command.command) .. " - " .. command.description)
    end
end
