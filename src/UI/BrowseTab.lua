local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

local ICON_W = 18
local LEVEL_W = 44
local IMPORTANCE = { "Minor tale", "Notable tale", "Major tale" }
local KIND = { dungeon = "Leads into a dungeon", raid = "Leads into a raid", class = "Class quest" }

local function SortedStoriesFor(act)
    local list = {}
    for _, story in ipairs(Lore.myStories) do
        if Lore:GetAct(story) == act then
            list[#list + 1] = story
        end
    end
    table.sort(list, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.importance > b.importance
    end)
    return list
end

local function StoryRow(L, story)
    local done = Lore:IsStoryComplete(story)
    local fits = not done and Lore:FitsPlayer(story)
    local row = L:Row(20, 1)

    if done then
        UI.RowIcon(row, Theme.textures.check, 14, 0)
    elseif story.importance == 3 then
        UI.RowIcon(row, Theme.textures.major, 12, 1)
    end

    local name = UI.RowText(row, story.name, { x = ICON_W, width = L.width - ICON_W - LEVEL_W - 8, wrap = false,
        size = 13, color = (done and "faded") or (fits and "accent") or "ink" })

    -- Dotted-leader stand-in: a hairline from the end of the name to the level.
    local nameEnd = ICON_W + math.min(name:GetStringWidth(), name:GetWidth()) + 4
    local leader = UI.texturePool:Acquire()
    local c = Theme.colors.faded
    leader:SetColorTexture(c[1], c[2], c[3], 0.35)
    leader:SetSize(math.max(L.width - LEVEL_W - nameEnd - 4, 1), 1)
    leader:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", nameEnd, 5)

    UI.RowText(row, story.minLevel .. "-" .. story.maxLevel, { anchor = "RIGHT", width = LEVEL_W,
        justify = "RIGHT", wrap = false, size = 12, color = "faded" })

    local lines = { story.name, story.zone .. " - levels " .. story.minLevel .. "-" .. story.maxLevel,
        IMPORTANCE[story.importance] .. ", " .. Lore:GetQuestCount(story) .. " quests" }
    if KIND[story.kind] then
        lines[#lines + 1] = KIND[story.kind]
    end
    if done then
        lines[#lines + 1] = "Recorded in your journal."
    elseif fits then
        lines[#lines + 1] = "Fits your level."
    end
    lines[#lines + 1] = "Click to read about it."
    UI.AddTooltip(row, lines)
    row:SetScript("OnClick", function() UI.ShowStory(story) end)
end

-- Story preview ------------------------------------------------------------------
-- Clicking a tale (here, in the Current Tale suggestions or in the Journal) opens its page
-- in the Chronicle: what it is, how far you've got, every chapter, and where to go.

local listScroll = 0

function UI.ShowStory(story)
    if UI.activeTab == "browse" and not UI.preview then
        listScroll = UI.frame.scroll:GetVerticalScroll() or 0
    else
        listScroll = 0
    end
    UI.SelectTab("browse")
    UI.preview = story.id
    UI.Refresh()
end

local function BackToList()
    UI.preview = nil
    UI.Refresh()
    UI.frame.scroll:SetVerticalScroll(listScroll)
end

-- Where the player stands with this tale, in a sentence.
local function Status(story, progress, current)
    local entry = Lore:GetJournalEntry(story.id)
    if entry and entry.completedAt then
        return ("Completed on the %s at level %d."):format(UI.FormatDay(entry.completedAt), entry.level or 0)
    elseif entry or Lore:IsStoryComplete(story) then
        return "Completed before Lore."
    end
    local total = #story.quests
    local status
    if current then
        status = ("Your current tale: chapter %s of %s."):format(UI.Roman(progress.activeIndex), UI.Roman(total))
    elseif progress.done > 0 then
        status = ("%d of %d chapters done."):format(progress.done, total)
    else
        status = ("Not yet begun. %d chapters."):format(total)
    end
    local level = Lore:PlayerLevel()
    if level < story.minLevel - 2 then
        status = status .. (" Best from level %d; you're %d."):format(story.minLevel, level)
    end
    return status
end

-- The chapter to send the player to: the one in their log, else the first not done.
local function NextIndex(progress)
    if progress.activeIndex then return progress.activeIndex end
    for i, state in ipairs(progress.states) do
        if state == "next" then return i end
    end
end

local function RenderPreview(L, story)
    local back = L:Row(18, 6)
    UI.RowText(back, "< Back to the Chronicle", { size = 12, color = "accent", wrap = false })
    back:SetScript("OnClick", BackToList)

    local progress = Lore:GetStoryProgress(story)
    local current = Lore:GetCurrentStory() == story
    local kind = IMPORTANCE[story.importance]
    if KIND[story.kind] then kind = kind .. " - " .. KIND[story.kind]:lower() end

    L:Text(kind, { font = "title", size = 13, color = "accent", justify = "CENTER", gap = 2 })
    L:Text(story.name, { font = "title", size = 20, justify = "CENTER", gap = 2 })
    L:Text(("%s - levels %d-%d"):format(story.zone, story.minLevel, story.maxLevel),
        { size = 11, color = "faded", justify = "CENTER", gap = 6 })
    L:Text(Status(story, progress, current), { size = 13, justify = "CENTER", gap = 8 })

    local index = not Lore:IsStoryComplete(story) and NextIndex(progress)
    if index then
        local label = progress.done == 0 and not progress.activeIndex and "Show me where it starts"
            or "Show me where it continues"
        L:Button(label, 190, (L.width - 190) / 2, function() Lore:ShowOnMap(story, index) end)
        L:Space(4)
    end
    L:Divider()

    UI.ChapterList(L, story, progress, index)
end

UI.RegisterTab({
    key = "browse",
    order = 2,
    title = "Chronicle",
    icon = Theme.tabIcons.browse,
    Render = function(L)
        local preview = UI.preview and Lore.storiesById[UI.preview]
        if preview then
            RenderPreview(L, preview)
            return
        end

        L:Text("The Chronicle of the " .. Lore.faction, { font = "title", size = 20, justify = "CENTER", gap = 2 })
        L:Text(("Level %d - %s"):format(Lore:PlayerLevel(), GetRealZoneText()),
            { size = 11, color = "faded", justify = "CENTER", gap = 8 })
        L:Divider()

        for _, act in ipairs(Lore.acts) do
            local stories = SortedStoriesFor(act)
            if #stories > 0 then
                L:Text(act.name, { font = "title", size = 19, color = "accent", gap = 4 })
                L:Divider(6)
                for _, story in ipairs(stories) do
                    StoryRow(L, story)
                end
                L:Space(10)
            end
        end

        L:Text(Theme.accentName .. " tales fit your level. Diamonds mark major tales. Click a tale to read it.",
            { size = 11, color = "faded", justify = "CENTER" })
    end,
})
