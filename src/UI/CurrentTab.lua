local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

local NUMERAL_W = 30
local ICON_X = 28
local NAME_X = 46
local ZONE_W = 96

-- Chapters the player opened by hand. The active chapter is always open.
local opened = {}

local STATE_ICON = {
    done = Theme.textures.check,
    active = Theme.textures.activeQuest,
    next = Theme.textures.availableQuest,
}

local function ToggleChapter(key)
    opened[key] = not opened[key]
    UI.Refresh()
end

local function CollapsedChapter(L, quest, index, state, key)
    local row = L:Row(22, 1)
    local muted = state == "done"
    UI.RowText(row, UI.Roman(index), { font = "title", size = 12, width = NUMERAL_W,
        color = muted and "faded" or "ink" })
    if STATE_ICON[state] and not (state == "next" and Lore:IsQuestLevelLocked(quest)) then
        UI.RowIcon(row, STATE_ICON[state], 14, ICON_X)
    end
    UI.RowText(row, quest.name, { x = NAME_X, width = L.width - NAME_X - ZONE_W - 4, wrap = false,
        size = 13, color = muted and "faded" or "ink" })
    UI.RowText(row, quest.zone or "", { anchor = "RIGHT", width = ZONE_W, justify = "RIGHT",
        wrap = false, size = 11, color = "faded" })
    row:SetScript("OnClick", function() ToggleChapter(key) end)
    local lines = { quest.name }
    local requirement = Lore:QuestLevelRequirement(quest)
    if requirement then lines[#lines + 1] = requirement end
    if quest.giver then lines[#lines + 1] = "Given by " .. quest.giver end
    lines[#lines + 1] = "Click to read."
    UI.AddTooltip(row, lines)
end

-- A chapter can need a quest that Lore tells as part of another tale (quest.after). Until
-- it's done, say which one, so the player knows why the quest isn't offered yet.
local function Prerequisites(L, quest)
    for _, questID in ipairs(quest.after or {}) do
        local other, index = Lore:GetChapter(questID)
        if other and not Lore:IsQuestDone(questID) then
            L:Text(("Needs %s from %s first (chapter %s)."):format(other.quests[index].name, other.name, UI.Roman(index)),
                { indent = NUMERAL_W, size = 12, color = "accent", gap = 8 })
        end
    end
end

local function OpenChapter(L, story, quest, index, state, key, pinned)
    L:Space(4)
    local row = L:Row(22, 4)
    UI.RowText(row, UI.Roman(index), { font = "title", size = 13, width = NUMERAL_W, color = "accent" })
    UI.RowText(row, quest.name, { font = "title", size = 16, x = NUMERAL_W, wrap = false, color = "accent" })
    if not pinned then
        row:SetScript("OnClick", function() ToggleChapter(key) end)
    end

    if state ~= "done" then Prerequisites(L, quest) end
    local requirement = Lore:QuestLevelRequirement(quest)
    if requirement then
        local locked = state ~= "done" and state ~= "active" and Lore:IsQuestLevelLocked(quest)
        L:Text(requirement .. (locked and " to accept this quest." or "."),
            { indent = NUMERAL_W, size = 12, color = locked and "accent" or "faded", gap = 8 })
    end
    -- Blizzard's text, then the practical details as their own block under a small heading.
    if quest.summary then
        L:Text(Lore:FormatQuestText(quest.summary), { indent = NUMERAL_W, size = 13, gap = 14 })
    end
    if quest.objective then
        L:Text("Objective", { font = "title", indent = NUMERAL_W, size = 13, color = "accent", gap = 3 })
        L:Text(Lore:FormatQuestText(quest.objective), { indent = NUMERAL_W, size = 12, gap = 6 })
    end
    if quest.giver then
        local zone = quest.zone and (" - " .. quest.zone) or ""
        L:Text("Given by " .. quest.giver .. zone, { indent = NUMERAL_W, size = 11, color = "faded", gap = 10 })
    end
    L:Button("Show on the map", 130, NUMERAL_W, function() Lore:ShowOnMap(story, index) end)
    L:Space(4)
end

-- Every chapter of a story, top-down. Chapters in your log and the one at openIndex are
-- always expanded; the rest are collapsed until clicked.
function UI.ChapterList(L, story, progress, openIndex)
    for i, quest in ipairs(story.quests) do
        local state = progress.states[i]
        local key = story.id .. ":" .. i
        local pinned = i == openIndex or state == "active"
        if pinned or opened[key] then
            OpenChapter(L, story, quest, i, state, key, pinned)
        else
            CollapsedChapter(L, quest, i, state, key)
        end
    end
end

local function SuggestionRows(L, stories)
    for _, story in ipairs(stories) do
        local row = L:Row(20, 1)
        UI.RowText(row, story.name, { width = L.width - 140, wrap = false, size = 13 })
        UI.RowText(row, story.zone .. "  " .. story.minLevel .. "-" .. story.maxLevel,
            { anchor = "RIGHT", width = 136, justify = "RIGHT", wrap = false, size = 11, color = "faded" })
        row:SetScript("OnClick", function() UI.ShowStory(story) end)
        UI.AddTooltip(row, { story.name, story.zone, Lore:GetQuestCount(story) .. " quests", "Click to read about it." })
    end
end

local function RenderEmpty(L)
    L:Text("No Tale Underway", { font = "title", size = 20, justify = "CENTER", gap = 6 })
    L:Text("Pick up a quest from any tale in the Chronicle and Lore will follow it from your quest log.",
        { size = 13, justify = "CENTER", color = "faded", gap = 10 })
    L:Divider()
    L:Text("Tales for your level", { font = "title", size = 14, color = "accent", gap = 6 })
    local suggestions = Lore:SuggestStories(6)
    if #suggestions > 0 then
        SuggestionRows(L, suggestions)
    else
        L:Text(Lore:GetSuggestionGuidance(), { size = 13, color = "faded", gap = 6 })
    end
end

UI.RegisterTab({
    key = "current",
    order = 1,
    title = "Current Tales",
    icon = Theme.tabIcons.current,
    Render = function(L)
        local current = Lore:GetCurrentStories()
        if #current == 0 then
            RenderEmpty(L)
            return
        end

        local selectedStoryID = Lore.db.currentStoryID
        local selected = current[1]
        for _, item in ipairs(current) do
            if item.story.id == selectedStoryID then selected = item end
        end
        selectedStoryID = selected.story.id
        Lore.db.currentStoryID = selectedStoryID

        if #current > 1 then
            L:Text(("%d tales underway"):format(#current),
                { font = "title", size = 20, justify = "CENTER", gap = 6 })
            for _, item in ipairs(current) do
                local tale = item.story
                local isSelected = tale.id == selectedStoryID
                local row = L:Row(24, 2)
                UI.RowIcon(row, Theme.textures.activeQuest, 14, 0)
                UI.RowText(row, tale.name, { x = 22, width = L.width - 96,
                    font = isSelected and "title" or "body", size = 14,
                    color = isSelected and "accent" or "ink" })
                UI.RowText(row, isSelected and "Reading" or "Read tale", { anchor = "RIGHT",
                    width = 70, justify = "RIGHT", size = 11, color = "faded" })
                row:SetScript("OnClick", function()
                    Lore.db.currentStoryID = tale.id
                    UI.frame.scroll:SetVerticalScroll(0)
                    UI.Refresh()
                end)
                UI.AddTooltip(row, { tale.name,
                    tale.quests[item.progress.activeIndex or item.progress.nextIndex].name, "Click to follow this tale." })
            end
            L:Divider()
        end

        local story, progress = selected.story, selected.progress
        local chapter = progress.activeIndex or progress.nextIndex
        L:Text(("Chapter %s of %s"):format(UI.Roman(chapter), UI.Roman(#story.quests)),
            { font = "title", size = 13, color = "accent", justify = "CENTER", gap = 2 })
        L:Text(story.name, { font = "title", size = 20, justify = "CENTER", gap = 2 })
        L:Text(story.zone .. " - " .. Lore:LevelText(story),
            { size = 11, color = "faded", justify = "CENTER", gap = 8 })
        L:Divider()
        UI.ChapterList(L, story, progress, chapter)

        local after = {}
        for _, suggestion in ipairs(Lore:SuggestStories(#Lore.myStories)) do
            local suggestedProgress = Lore:GetStoryProgress(suggestion)
            if not suggestedProgress.activeIndex and suggestedProgress.done == 0 and #after < 2 then
                after[#after + 1] = suggestion
            end
        end
        if #after > 0 then
            L:Space(8)
            L:Divider()
            L:Text("More tales for your level", { font = "title", size = 14, color = "accent", gap = 6 })
            SuggestionRows(L, after)
        end
    end,
})
