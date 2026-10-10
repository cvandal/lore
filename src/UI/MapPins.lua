local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

-- Lore's own pins on the world map and minimap, placed through HereBeDragons. They only
-- point at things the game can't: quests already in your log get the game's own markers,
-- so Lore never pins those.
--   * Current tale: where the next chapter starts.
--   * No current tale: where the suggested tales for your level start, nearby first.
--   * "Show on the map": one chapter the player picked, from any story, unless the map
--     already marks it (it's in your log, or already has a Lore pin).

local HBDPins = LibStub("HereBeDragonsLore-Pins-2.0")
local PIN_REF = "Lore"
local WORLD_SIZE, MINIMAP_SIZE = 20, 16
local SUGGESTION_PINS = 5

-- Draw above the game's own quest markers, which would otherwise hide a Lore pin at the
-- same spot. Only used when the map actually has that layer.
local topLayer
local function TopLayer()
    if topLayer == nil then
        topLayer = false
        local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
        if manager and manager.GetValidFrameLevel then
            local ok, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_TOPMOST")
            if ok and type(level) == "number" then topLayer = "PIN_FRAME_LEVEL_TOPMOST" end
        end
    end
    return topLayer or nil
end

local worldPool, minimapPool = {}, {}
local used = {}

local function OnEnter(pin)
    local info = pin.info
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(info.title, 1, 0.82, 0)
    GameTooltip:AddLine(info.story, 1, 1, 1)
    GameTooltip:AddLine(info.action, 0.8, 0.8, 0.8)
    if info.objective then
        GameTooltip:AddLine(info.objective, 1, 1, 1, true)
    end
    GameTooltip:AddLine("Click to open Lore.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function CreatePin(size)
    local pin = CreateFrame("Button", nil, UIParent)
    pin:SetSize(size, size)

    -- The Lore bookmark icon, cut into a circle, with a small quest marker in the corner.
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture(Theme.tabIcons.current)
    pin.icon:SetMask(Theme.textures.circleMask)

    pin.marker = pin:CreateTexture(nil, "OVERLAY")
    pin.marker:SetSize(size * 0.6, size * 0.6)
    pin.marker:SetPoint("BOTTOMRIGHT", size * 0.2, -size * 0.15)

    pin:SetHighlightTexture(Theme.textures.tabHighlight, "ADD")
    pin:SetScript("OnEnter", OnEnter)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function()
        if not (UI.frame and UI.frame:IsShown()) then Lore:Toggle() end
    end)
    return pin
end

local function Acquire(pool, size)
    local pin = table.remove(pool) or CreatePin(size)
    pin.pool = pool
    used[#used + 1] = pin
    return pin
end

local function ReleaseAll()
    HBDPins:RemoveAllWorldMapIcons(PIN_REF)
    HBDPins:RemoveAllMinimapIcons(PIN_REF)
    for i = #used, 1, -1 do
        local pin = used[i]
        pin:Hide()
        pin.pool[#pin.pool + 1] = pin
        used[i] = nil
    end
end

-- Where a chapter's pin goes: the turn-in while it's in your log, otherwise where it starts.
local function ChapterSpot(quest, state)
    if state == "active" and quest.enderMap then
        return quest.enderMap, quest.enderX, quest.enderY, quest.ender, quest.enderInside, true
    end
    if quest.giverMap then
        return quest.giverMap, quest.giverX, quest.giverY, quest.giver, quest.giverInside, false
    end
    if quest.enderMap then
        return quest.enderMap, quest.enderX, quest.enderY, quest.ender, quest.enderInside, true
    end
end

local function AddPin(story, quest, state, opts)
    local uiMapID, x, y, who, inside, turnIn = ChapterSpot(quest, state)
    if not uiMapID then return end

    local action = (turnIn and "Turn in to " or "Starts with ") .. (who or "?")
    if inside then
        action = action .. " (inside " .. inside .. ")"
    end
    local info = {
        title = quest.name,
        story = story.name,
        action = action,
        objective = opts.withObjective and quest.objective and Lore:FormatQuestText(quest.objective) or nil,
    }
    local marker = turnIn and Theme.textures.activeQuest or Theme.textures.availableQuest

    local worldPin = Acquire(worldPool, WORLD_SIZE)
    worldPin.info = info
    worldPin.marker:SetTexture(marker)
    HBDPins:AddWorldMapIconMap(PIN_REF, worldPin, uiMapID, x / 100, y / 100, opts.showFlag, TopLayer())

    if opts.minimap then
        local miniPin = Acquire(minimapPool, MINIMAP_SIZE)
        miniPin.info = info
        miniPin.marker:SetTexture(marker)
        HBDPins:AddMinimapIconMap(PIN_REF, miniPin, uiMapID, x / 100, y / 100, false, true)
    end
end

-- The first chapter after the one(s) in your log that you haven't started: the next step
-- the game knows nothing about.
local function NextChapter(progress)
    for i = (progress.activeIndex or 0) + 1, #progress.states do
        if progress.states[i] == "upcoming" or progress.states[i] == "next" then
            return i
        end
    end
end

local pinned = {}  -- ["storyID:index"] = true for each chapter with a Lore pin

local function PinChapter(story, index, state, opts)
    AddPin(story, story.quests[index], state, opts)
    pinned[story.id .. ":" .. index] = true
end

-- Pins for the current tale's next chapter or, without one, the suggested tales.
local function AutomaticPins(self)
    local story, progress = self:GetCurrentStory()
    if story then
        local index = NextChapter(progress)
        if index then
            PinChapter(story, index, progress.states[index],
                { minimap = true, withObjective = true, showFlag = HBD_PINS_WORLDMAP_SHOW_PARENT })
        end
        return
    end
    for _, suggestion in ipairs(self:SuggestStories(SUGGESTION_PINS)) do
        local first = self:GetStoryProgress(suggestion)
        for i, state in ipairs(first.states) do
            if state == "next" then
                PinChapter(suggestion, i, state, { showFlag = HBD_PINS_WORLDMAP_SHOW_CURRENT })
                break
            end
        end
    end
end

function Lore:RefreshPins()
    ReleaseAll()
    wipe(pinned)
    if not (self.db and self.db.settings.pins and self.faction) then return end
    AutomaticPins(self)

    -- The chapter the player asked to see, unless it's now in the log (the game marks it).
    local marked = self.marked and self.storiesById[self.marked.storyID]
    if marked and not pinned[marked.id .. ":" .. self.marked.index] then
        local state = self:GetStoryProgress(marked).states[self.marked.index]
        if state ~= "active" then
            PinChapter(marked, self.marked.index, state,
                { minimap = true, withObjective = true, showFlag = HBD_PINS_WORLDMAP_SHOW_PARENT })
        end
    end
end

-- Open the world map the way the game does. On WoW Forever a raw WorldMapFrame:Show() doesn't
-- open it properly (Questie's Forever notes); HandleUserActionOpenSelf is the game's own path.
local function OpenWorldMap(uiMapID)
    if not WorldMapFrame:IsShown() then
        if WorldMapFrame.HandleUserActionOpenSelf then
            WorldMapFrame:HandleUserActionOpenSelf()
        elseif ShowUIPanel then
            ShowUIPanel(WorldMapFrame)
        else
            WorldMapFrame:Show()
        end
    end
    WorldMapFrame:SetMapID(uiMapID)
end

-- "Show on the map": open the world map on this chapter, adding a Lore pin only where the
-- map doesn't already mark it. Returns how it's marked: "game", "pinned" or "marked".
function Lore:ShowOnMap(story, index)
    local quest = story.quests[index]
    local state = self:GetStoryProgress(story).states[index]
    local uiMapID, _, _, who, inside, turnIn = ChapterSpot(quest, state)
    if not uiMapID then
        self:Print("Lore doesn't know where " .. quest.name .. " takes place.")
        return
    end

    local how
    if state == "active" then
        how = "game"     -- in your log: the game's own marker shows the way
    else
        self.db.settings.pins = true
        self:RefreshPins()
        if pinned[story.id .. ":" .. index] then
            how = "pinned"   -- already has a Lore pin (the next chapter, or a suggestion)
        else
            self.marked = { storyID = story.id, index = index }
            self:RefreshPins()
            how = "marked"
        end
    end
    OpenWorldMap(uiMapID)

    local where = ("%s %s%s"):format(turnIn and "turn in to" or "starts with", who or "?",
        inside and (" (inside " .. inside .. ")") or "")
    if how == "game" then
        self:Print(("%s is in your quest log, so the game marks it: %s."):format(quest.name, where))
    elseif how == "pinned" then
        self:Print(("%s already has a Lore pin: %s."):format(quest.name, where))
    else
        self:Print(("Pinned %s on the map: %s."):format(quest.name, where))
    end
    return how
end
