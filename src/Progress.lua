local _, Lore = ...

-- Story lookup tables ----------------------------------------------------------

Lore.stories = {}         -- the player's faction's, set by LoadStories at login
Lore.storiesById = {}
Lore.questToStory = {}    -- [questID] = story
Lore.questToChapter = {}  -- [questID] = chapter index within that story

function Lore:LoadStories(faction)
    self.stories = self.storyData[faction]
    self.acts = self.actsByFaction[faction]
    local _, _, classID = UnitClass("player")
    for _, story in ipairs(self.stories) do
        for _, quest in ipairs(story.quests) do
            for _, variant in ipairs(quest.variants or {}) do
                if variant.classID == classID then
                    for key, value in pairs(variant) do
                        if key ~= "ids" and key ~= "classID" then quest[key] = value end
                    end
                end
            end
        end
        self.storiesById[story.id] = story
        for index, quest in ipairs(story.quests) do
            for _, questID in ipairs(quest.ids) do
                self.questToStory[questID] = story
                self.questToChapter[questID] = index
            end
        end
    end
end

-- The story and chapter number a quest belongs to, if any.
function Lore:GetChapter(questID)
    local story = questID and self.questToStory[questID]
    if story then return story, self.questToChapter[questID] end
end

local function Contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Stories this character's race and class can do. Built once at login.
Lore.myStories = {}

function Lore:BuildMyStories()
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    wipe(self.myStories)
    for _, story in ipairs(self.stories) do
        local raceOK = not story.races or Contains(story.races, raceID)
        local classOK = not story.classes or Contains(story.classes, classID)
        if raceOK and classOK then
            self.myStories[#self.myStories + 1] = story
        end
    end
end

function Lore:GetQuestCount(story)
    return #story.quests
end

function Lore:GetAct(story)
    for _, act in ipairs(self.acts) do
        if story.minLevel <= act.maxLevel then return act end
    end
    return self.acts[#self.acts]
end

-- Quest text ---------------------------------------------------------------------

local GENDER_INDEX = { [2] = 1, [3] = 2 }  -- UnitSex: 2 male, 3 female

-- Blizzard's placeholders: $N name, $C class, $R race, $B line break, $Gmale:female;
function Lore:FormatQuestText(text)
    if not text or text == "" then return "" end
    local name = UnitName("player")
    local class = UnitClass("player")
    local race = UnitRace("player")
    local gender = GENDER_INDEX[UnitSex("player")] or 1
    text = text:gsub("%$[Gg]%s*([^:;]*):([^;]*);", function(male, female)
        return gender == 1 and male or female
    end)
    text = text:gsub("%$[Bb]", "\n")
    text = text:gsub("%$[Nn]", name)
    text = text:gsub("%$[Cc]", class:lower())
    text = text:gsub("%$[Rr]", race)
    return text
end

-- Quest state ------------------------------------------------------------------

local function IsQuestIDCompleted(questID)
    if Lore.db and Lore.db.completedQuests[questID] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(questID) or false
end

function Lore:IsQuestDone(questID)
    return IsQuestIDCompleted(questID)
end

-- WoW Forever has the newer C_QuestLog API; older clients only have GetQuestLogTitle.
local function GetQuestLogEntry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if info then return info.questID, info.isHeader end
        return nil, true
    end
    local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    return questID, isHeader
end

local function GetQuestLogIDs()
    local inLog = {}
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
        and C_QuestLog.GetNumQuestLogEntries() or GetNumQuestLogEntries()
    for i = 1, numEntries do
        local questID, isHeader = GetQuestLogEntry(i)
        if not isHeader and questID then
            inLog[questID] = true
        end
    end
    return inLog
end

-- A chapter's ids are alternatives (race or class versions of the same quest),
-- so doing any one of them completes it.
local function IsChapterDone(quest)
    for _, questID in ipairs(quest.ids) do
        if IsQuestIDCompleted(questID) then return true end
    end
    return false
end

local function IsChapterInLog(quest, inLog)
    for _, questID in ipairs(quest.ids) do
        if inLog[questID] then return true end
    end
    return false
end

-- Returns { states = { "done" | "active" | "next" | "upcoming", ... }, done, activeIndex }
function Lore:GetStoryProgress(story, inLog)
    inLog = inLog or GetQuestLogIDs()
    local progress = { states = {}, done = 0 }
    for i, quest in ipairs(story.quests) do
        if IsChapterDone(quest) then
            progress.states[i] = "done"
            progress.done = progress.done + 1
        elseif IsChapterInLog(quest, inLog) then
            progress.states[i] = "active"
            progress.activeIndex = progress.activeIndex or i
        else
            progress.states[i] = "upcoming"
        end
    end
    if not progress.activeIndex then
        for i, state in ipairs(progress.states) do
            if state == "upcoming" then
                progress.states[i] = "next"
                break
            end
        end
    end
    return progress
end

function Lore:GetJournalEntry(storyID)
    return self.db.journal[storyID]
end

function Lore:IsStoryComplete(story)
    if self:GetJournalEntry(story.id) then return true end
    return IsChapterDone(story.quests[#story.quests])
end

-- All unfinished tales with a quest in the log, ordered by importance and progress.
function Lore:GetCurrentStories()
    local inLog = GetQuestLogIDs()
    local list = {}
    for _, story in ipairs(self.myStories) do
        if not self:IsStoryComplete(story) then
            local progress = self:GetStoryProgress(story, inLog)
            if progress.activeIndex then
                list[#list + 1] = { story = story, progress = progress }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.story.importance ~= b.story.importance then
            return a.story.importance > b.story.importance
        end
        if a.progress.done ~= b.progress.done then return a.progress.done > b.progress.done end
        return a.story.id < b.story.id
    end)
    return list
end

-- Keep the primary tale available to callers that need a single story.
function Lore:GetCurrentStory()
    local current = self:GetCurrentStories()[1]
    if current then return current.story, current.progress end
end

-- Suggestions --------------------------------------------------------------------

function Lore:PlayerLevel()
    return UnitLevel("player")
end

function Lore:FitsPlayer(story)
    local level = self:PlayerLevel()
    return level >= story.minLevel - 2 and level <= story.maxLevel
end

-- Early adventures stay in the current zone; later tales can lead farther afield.
function Lore:SuggestStories(limit, excludeID)
    local zone = GetRealZoneText()
    local list = {}
    local localOnly = self:PlayerLevel() < 10
    for _, story in ipairs(self.myStories) do
        if (not localOnly or story.zone == zone) and story.id ~= excludeID
            and self:FitsPlayer(story) and not self:IsStoryComplete(story) then
            list[#list + 1] = story
        end
    end
    table.sort(list, function(a, b)
        local aNear, bNear = a.zone == zone, b.zone == zone
        if aNear ~= bNear then return aNear end
        if a.importance ~= b.importance then return a.importance > b.importance end
        return a.minLevel < b.minLevel
    end)
    while #list > limit do table.remove(list) end
    return list
end

-- Give new characters a useful next step when their zone has no suitable tale yet.
function Lore:GetSuggestionGuidance()
    local zone = GetRealZoneText()
    local nextLevel
    for _, story in ipairs(self.myStories) do
        local level = math.max(1, story.minLevel - 2)
        if story.zone == zone and level > self:PlayerLevel() and not self:IsStoryComplete(story) then
            nextLevel = math.min(nextLevel or level, level)
        end
    end
    if nextLevel then
        return ("Continue your adventures in %s. Lore's next local tale fits your level from level %d.")
            :format(zone, nextLevel)
    end
    return ("Continue your adventures in %s. Explore the Chronicle for tales in other zones."):format(zone)
end

-- Journal --------------------------------------------------------------------------

function Lore:RecordCompletion(story, preLore)
    if self.db.journal[story.id] then return end
    if preLore then
        self.db.journal[story.id] = { preLore = true }
    else
        self.db.journal[story.id] = {
            completedAt = time(),
            level = UnitLevel("player"),
            zone = GetRealZoneText(),
        }
        self:Say(("Tale complete: |cffffffff%s|r. It's written in your journal."):format(story.name))
    end
end

-- Messages as the story moves on ---------------------------------------------------

-- Lore's story messages, which /lore messages turns off.
function Lore:Say(msg)
    if self.db.settings.messages then self:Print(msg) end
end

-- "Ak'Zeloth, chapter III of VII", with the tale's name in white.
local function ChapterOf(story, index)
    return ("|cffffffff%s|r, chapter %s of %s"):format(story.name, Lore.UI.Roman(index), Lore.UI.Roman(#story.quests))
end

-- Picking up a story quest: a new tale, or the next chapter of one you're on.
function Lore:OnQuestAccepted(questID)
    local story, index = self:GetChapter(questID)
    if not story or self:IsStoryComplete(story) then return end
    local progress = self:GetStoryProgress(story)
    if progress.done == 0 then
        self:Say(("A new tale begins: |cffffffff%s|r, %d chapters. Type /lore to read it.")
            :format(story.name, #story.quests))
    else
        self:Say(("%s: %s."):format(ChapterOf(story, index), story.quests[index].name))
    end
end

function Lore:OnQuestTurnedIn(questID)
    if self.questToStory[questID] then self.db.completedQuests[questID] = true end
    local story, index = self:GetChapter(questID)
    if not story then return end
    if self:IsStoryComplete(story) then
        self:RecordCompletion(story, false)
        return
    end
    -- Where the tale goes next: the first chapter after this one that isn't done.
    local progress = self:GetStoryProgress(story)
    for i = index + 1, #story.quests do
        if progress.states[i] ~= "done" then
            local quest = story.quests[i]
            local from = quest.giver and (", from " .. quest.giver) or ""
            self:Say(("%s done. Next: %s%s."):format(ChapterOf(story, index), quest.name, from))
            return
        end
    end
end

-- Stories finished before Lore was installed have no date.
function Lore:RecordPreLoreCompletions()
    for _, story in ipairs(self.myStories) do
        if not self.db.journal[story.id] and IsChapterDone(story.quests[#story.quests]) then
            self:RecordCompletion(story, true)
        end
    end
end

-- Newest first; undated (pre-Lore) entries last.
function Lore:GetJournalEntries()
    local list = {}
    for _, story in ipairs(self.stories) do
        local entry = self:GetJournalEntry(story.id)
        if entry then
            list[#list + 1] = { story = story, entry = entry }
        end
    end
    table.sort(list, function(a, b)
        local ta, tb = a.entry.completedAt or 0, b.entry.completedAt or 0
        if ta ~= tb then return ta > tb end
        return a.story.minLevel < b.story.minLevel
    end)
    return list
end
