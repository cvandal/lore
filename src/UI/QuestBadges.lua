local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

-- Marks story quests wherever you see them (the Story badges option turns it all off):
--   * A small Lore badge on story quests in an NPC's quest list (gossip and quest greetings).
--   * A tag beside the quest window naming the tale and chapter, on the quest's detail,
--     progress and reward pages.
--   * The tale and chapter in the tooltip of a story quest's title in the quest log.
-- Blizzard's buttons also drive the gamepad UI, so Lore never replaces their scripts or
-- icons: it adds its own texture to the button and hooks the tooltip.

local BADGE_SIZE = 16
local RING_ALPHA = 0.5  -- a hint of gold: full strength was too loud next to quest titles

-- Which chapter a quest list entry is ----------------------------------------------

-- Lists without quest IDs (older clients) fall back to the title, and only count when the
-- NPC is the one Lore expects to give (or take) that quest, so same-named filler isn't marked.
local byTitle
local function FindByTitle(title, active)
    if not title or title == "" then return end
    if not byTitle then
        byTitle = {}
        for _, story in ipairs(Lore.stories) do
            for index, quest in ipairs(story.quests) do
                byTitle[quest.name] = byTitle[quest.name] or {}
                table.insert(byTitle[quest.name], { story = story, index = index, quest = quest })
            end
        end
    end
    local npc = UnitName("npc")
    for _, match in ipairs(byTitle[title] or {}) do
        if npc and npc == (active and match.quest.ender or match.quest.giver) then
            return match.story, match.index
        end
    end
end

local function FindChapter(questID, title, active)
    if questID and questID > 0 then
        return Lore:GetChapter(questID)
    end
    return FindByTitle(title, active)
end

local function ChapterLine(story, index)
    return ("Chapter %s of %s"):format(UI.Roman(index), UI.Roman(#story.quests))
end

-- Badges on quest list buttons ---------------------------------------------------

local badges = setmetatable({}, { __mode = "k" })   -- [button] = icon texture (.ring = its gold ring)
local marked = setmetatable({}, { __mode = "k" })   -- [button] = { story, index } while badged

local hooked = setmetatable({}, { __mode = "k" })  -- [button] = true once its tooltip is hooked

local function ShowTooltip(button)
    local mark = marked[button]
    if not mark then return end
    if not GameTooltip:IsOwned(button) then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
    end
    GameTooltip:AddLine("Lore: " .. mark.story.name, 1, 0.82, 0)
    GameTooltip:AddLine(ChapterLine(mark.story, mark.index), 1, 1, 1)
    GameTooltip:Show()
end

local function HideTooltip(button)
    if marked[button] and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function HookTooltip(button)
    if hooked[button] then return end
    button:HookScript("OnEnter", ShowTooltip)
    button:HookScript("OnLeave", HideTooltip)
    hooked[button] = true
end

-- The badge sits at the button's right edge.
local function Badge(button)
    local badge = badges[button]
    if not badge then
        -- Top sublevels, so the badge draws over the button's own art.
        badge = button:CreateTexture(nil, "OVERLAY", nil, 6)
        badge:SetTexture(Theme.tabIcons.current)
        badge:SetMask(Theme.textures.circleMask)
        badge:SetSize(BADGE_SIZE, BADGE_SIZE)
        badge:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        -- The minimap button's gold ring, so the badge reads as Lore's. Same proportions as
        -- the minimap button: a 17px icon inside a 53px ring file, 7px in and 6px down.
        local scale = BADGE_SIZE / 17
        badge.ring = button:CreateTexture(nil, "OVERLAY", nil, 7)
        badge.ring:SetTexture(Theme.textures.minimapBorder)
        badge.ring:SetAlpha(RING_ALPHA)
        badge.ring:SetSize(53 * scale, 53 * scale)
        badge.ring:SetPoint("TOPLEFT", badge, "TOPLEFT", -7 * scale, 6 * scale)
        badges[button] = badge
    end
    return badge
end

-- For tests: the badge drawn on a button, if any.
function UI.BadgeOn(button) return badges[button] end

-- The tale and chapter in a button's tooltip (nil story clears it).
local function SetTooltip(button, story, index)
    if story and Lore.db.settings.badges then
        HookTooltip(button)
        marked[button] = { story = story, index = index }
    else
        marked[button] = nil
    end
end

-- Buttons are recycled, so every visible one is set: badged or cleared.
local function SetBadge(button, story, index)
    local show = story and Lore.db.settings.badges
    if show then
        local badge = Badge(button)
        badge:Show()
        badge.ring:Show()
    elseif badges[button] then
        badges[button]:Hide()
        badges[button].ring:Hide()
    end
    SetTooltip(button, story, index)
end

local count = 0
function UI.MarkGossip()
    count = 0
    local panel = GossipFrame and GossipFrame:IsShown() and GossipFrame.GreetingPanel
    if not (panel and panel.ScrollBox) then return count end
    panel.ScrollBox:ForEachFrame(function(button)
        local data = button.GetElementData and button:GetElementData()
        local info = data and data.info
        local story, index
        if info and (data.availableQuestButton or data.activeQuestButton) then
            story, index = FindChapter(info.questID, info.title, data.activeQuestButton)
        end
        SetBadge(button, story, index)
        if story then count = count + 1 end
    end)
    return count
end

-- Quest greetings: Forever pools unnamed buttons; older clients number them.
local function ForEachGreetingButton(callback)
    local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
    if pool then
        for button in pool:EnumerateActive() do
            if button:IsShown() then callback(button) end
        end
        return
    end
    for i = 1, MAX_NUM_QUESTS or 0 do
        local button = _G["QuestTitleButton" .. i]
        if not button then break end
        if button:IsShown() then callback(button) end
    end
end

function UI.MarkGreeting()
    count = 0
    ForEachGreetingButton(function(button)
        local active = button.isActive == 1
        local i = button:GetID()
        local questID
        if active and GetActiveQuestID then
            questID = GetActiveQuestID(i)
        elseif not active and GetAvailableQuestInfo then
            questID = select(5, GetAvailableQuestInfo(i))  -- Forever adds the ID in position 5
        end
        local story, index = FindChapter(questID, button:GetText(), active)
        SetBadge(button, story, index)
        if story then count = count + 1 end
    end)
    return count
end

-- The tag beside the quest window -----------------------------------------------

local tag

local function CreateTag()
    tag = CreateFrame("Button", "LoreQuestTag", QuestFrame, "BackdropTemplate")
    tag:SetHeight(46)
    tag:SetPoint("TOPLEFT", QuestFrame, "TOPRIGHT", -2, -64)
    tag:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Theme.textures.border,
        edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    local leather = Theme.colors.leather
    tag:SetBackdropColor(leather[1], leather[2], leather[3], 1)

    tag.icon = tag:CreateTexture(nil, "ARTWORK")
    tag.icon:SetSize(26, 26)
    tag.icon:SetPoint("LEFT", 10, 0)
    tag.icon:SetTexture(Theme.tabIcons.current)
    tag.icon:SetMask(Theme.textures.circleMask)

    tag.story = tag:CreateFontString(nil, "ARTWORK")
    tag.story:SetFont(Theme.fonts.title, 15)
    tag.story:SetTextColor(unpack(Theme.colors.gold))
    tag.story:SetPoint("TOPLEFT", tag.icon, "TOPRIGHT", 8, 2)
    tag.story:SetJustifyH("LEFT")

    tag.chapter = tag:CreateFontString(nil, "ARTWORK")
    tag.chapter:SetFont(Theme.fonts.body, 11)
    tag.chapter:SetTextColor(0.9, 0.85, 0.75)
    tag.chapter:SetPoint("TOPLEFT", tag.story, "BOTTOMLEFT", 0, -3)
    tag.chapter:SetJustifyH("LEFT")

    tag:SetScript("OnClick", function()
        if not (UI.frame and UI.frame:IsShown()) then Lore:Toggle() end
    end)
    tag:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Lore", 1, 0.82, 0)
        GameTooltip:AddLine("This quest is part of a story.", 1, 1, 1)
        GameTooltip:AddLine("Click to open the book.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    tag:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.UpdateQuestTag()
    if not QuestFrame then return end
    local story, index = Lore:GetChapter(GetQuestID and GetQuestID() or 0)
    if not story or not Lore.db.settings.badges then
        if tag then tag:Hide() end
        return
    end
    if not tag then CreateTag() end
    tag.story:SetText(story.name)
    local line = ChapterLine(story, index)
    if index == #story.quests and index > 1 then
        line = line .. ", the last"
    end
    tag.chapter:SetText(line)
    local textWidth = math.max(tag.story:GetStringWidth(), tag.chapter:GetStringWidth())
    tag:SetWidth(math.min(math.max(textWidth + 56, 150), 260))
    tag:Show()
    return story, index
end

local function HideTag()
    if tag then tag:Hide() end
end

-- Quest log tooltip --------------------------------------------------------------
-- Hovering a story quest's title in the quest log adds its tale and chapter to the tooltip.
-- Nothing is drawn on the quest log or the objective tracker: badges there were tried (after
-- the title, then on the quest's round icon) and looked out of place.
-- WoW Forever uses Retail's "Map & Quest Log": its titles come from
-- QuestScrollFrame.titleFramePool, buttons with .questID and .Text.

local function QuestLogTitles(callback)
    local scroll = QuestScrollFrame
    local pool = scroll and scroll.titleFramePool
    if pool and pool.EnumerateActive then
        for button in pool:EnumerateActive() do
            local questID = rawget(button, "questID")
            if button:IsShown() and questID and rawget(button, "Text") then callback(button, questID) end
        end
        return
    end
    local contents = scroll and scroll.Contents
    if not contents then return end
    for _, child in ipairs({ contents:GetChildren() }) do
        -- Objective lines and quest icons carry .questID too; only titles are buttons with text.
        local questID = rawget(child, "questID")
        if child:IsShown() and child:GetObjectType() == "Button" and type(questID) == "number" and rawget(child, "Text") then
            callback(child, questID)
        end
    end
end

function UI.MarkQuestLog()
    count = 0
    if not (Lore.db and Lore.isHorde) then return count end  -- Blizzard can redraw before login
    QuestLogTitles(function(button, questID)
        local story, index = Lore:GetChapter(questID)
        SetTooltip(button, story, index)
        if story and Lore.db.settings.badges then count = count + 1 end
    end)
    return count
end

-- Re-mark after Blizzard redraws the quest log. Its code may load after Lore, so this is
-- retried on ADDON_LOADED until the hook is in place.
local hookedLog
local function HookQuestLog()
    if not hookedLog and QuestLogQuests_Update then
        hooksecurefunc("QuestLogQuests_Update", UI.MarkQuestLog)
        hookedLog = true
    end
end

-- Events ------------------------------------------------------------------------

local events = CreateFrame("Frame")
UI.badgeEvents = events
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
    "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_LOG_UPDATE", "PLAYER_LOGIN", "ADDON_LOADED" }) do
    events:RegisterEvent(event)
end

-- Blizzard fills the lists in its own handler for the same event, so mark them a frame later.
local function Later(fn) C_Timer.After(0, fn) end

events:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        HookQuestLog()
        return
    end
    if not Lore.isHorde then return end
    if event == "GOSSIP_SHOW" then
        Later(UI.MarkGossip)
    elseif event == "QUEST_GREETING" then
        HideTag()
        Later(UI.MarkGreeting)
    elseif event == "QUEST_FINISHED" then
        HideTag()
    elseif event == "QUEST_LOG_UPDATE" then
        -- Accepting or handing in rebuilds an open list.
        if GossipFrame and GossipFrame:IsShown() then Later(UI.MarkGossip) end
        if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then Later(UI.MarkGreeting) end
        -- Belt and braces in case the hook isn't in place on this client.
        if not hookedLog then Later(UI.MarkQuestLog) end
    else
        UI.UpdateQuestTag()
    end
end)

-- /lore debug: what Lore sees in the NPC window and quest log right now.
function UI.DebugBadges()
    -- Also kept in the saved variables (LoreCharDB.lastDebug), written on /reload, so the
    -- whole report can be read from the file even when the chat window is too short.
    local lines = { date("%Y-%m-%d %H:%M:%S") }
    Lore.db.lastDebug = lines
    local function Out(text)
        lines[#lines + 1] = text
        Lore:Print(text)
    end
    local function Report(questID, title, active)
        local story, index = FindChapter(questID, title, active)
        Out(("  %s [%s] %s -> %s"):format(active and "active" or "available", tostring(questID),
            tostring(title), story and (story.name .. ", " .. ChapterLine(story, index)) or "not a story quest"))
    end
    Out("NPC: " .. tostring(UnitName("npc")) .. ", isHorde: " .. tostring(Lore.isHorde))

    local panel = GossipFrame and GossipFrame:IsShown() and GossipFrame.GreetingPanel
    Out("Gossip window: " .. (panel and "open" or "closed")
        .. (panel and (", ScrollBox: " .. tostring(panel.ScrollBox ~= nil)) or ""))
    if panel and panel.ScrollBox then
        local n = 0
        panel.ScrollBox:ForEachFrame(function(button)
            n = n + 1
            local data = button.GetElementData and button:GetElementData()
            local info = data and data.info
            if info and (data.availableQuestButton or data.activeQuestButton) then
                Report(info.questID, info.title, data.activeQuestButton)
            else
                Out("  line " .. n .. ": not a quest")
            end
        end)
        Out("  " .. n .. " lines, " .. UI.MarkGossip() .. " badged")
    end

    local greeting = QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown()
    Out("Quest greeting: " .. (greeting and "open" or "closed")
        .. (greeting and (", pooled buttons: " .. tostring(QuestFrameGreetingPanel.titleButtonPool ~= nil)) or ""))
    if greeting then
        Out("  " .. UI.MarkGreeting() .. " badged")
    end

    if QuestFrame and QuestFrame:IsShown() and GetQuestID then
        local questID = GetQuestID()
        Out("Quest window: quest " .. tostring(questID))
        Report(questID, nil, false)
        UI.UpdateQuestTag()
        Out("  tag shown: " .. tostring(tag ~= nil and tag:IsShown()))
    else
        Out("Quest window: closed")
    end

    Out("Story badges: " .. (Lore.db.settings.badges and "on" or "off"))
    local rows = {}
    QuestLogTitles(function(_, id)
        local story, index = Lore:GetChapter(id)
        rows[#rows + 1] = ("  [%d] %s"):format(id, story and (story.name .. ", " .. ChapterLine(story, index)) or "-")
    end)
    Out(("Quest log%s: %d quests, hooked: %s"):format(QuestScrollFrame and "" or " (not found)", #rows, tostring(hookedLog)))
    for _, line in ipairs(rows) do Out(line) end
    UI.MarkQuestLog()
    Lore:Print("Report saved. Type /reload to write it to disk.")
end
