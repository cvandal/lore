local _, Lore = ...

-- Everything visual lives here, so swapping a texture is a one-line change.
-- Paths are built-in Blizzard art, so Lore ships no images of its own.
local Theme = {}
Lore.Theme = Theme

Theme.fonts = {
    title = "Fonts\\MORPHEUS.TTF",
    body = "Fonts\\FRIZQT__.TTF",
}

Theme.colors = {
    -- Darkened for contrast on parchment; "faded" must stay readable at small sizes.
    ink = { 0.10, 0.06, 0.02 },
    crimson = { 0.48, 0.06, 0.03 },
    faded = { 0.27, 0.19, 0.10 },
    leather = { 0.29, 0.15, 0.09 },
    gold = { 1.0, 0.82, 0.0 },
}

Theme.textures = {
    page = "Interface\\QuestFrame\\QuestBG",
    border = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    header = "Interface\\DialogFrame\\UI-DialogBox-Header",
    tab = "Interface\\SpellBook\\SpellBook-SkillLineTab",
    crest = "Interface\\TargetingFrame\\UI-PVP-Horde",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    activeQuest = "Interface\\GossipFrame\\ActiveQuestIcon",
    availableQuest = "Interface\\GossipFrame\\AvailableQuestIcon",
    major = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    tabHighlight = "Interface\\Buttons\\ButtonHilight-Square",
    tabChecked = "Interface\\Buttons\\CheckButtonHilight",
    circleMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    minimapBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
    minimapBackground = "Interface\\Minimap\\UI-Minimap-Background",
    minimapHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
}

-- QuestBG's parchment only fills the top-left of its 512x512 file.
Theme.pageTexCoord = { 0, 0.5859375, 0, 0.65 }

Theme.tabIcons = {
    current = "Interface\\Icons\\INV_Misc_Note_01",
    browse = "Interface\\Icons\\INV_Misc_Note_02",
    journal = "Interface\\Icons\\INV_Misc_Book_09",
    settings = "Interface\\Icons\\INV_Misc_Gear_01",
}
