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
    faded = { 0.27, 0.19, 0.10 },
    gold = { 1.0, 0.82, 0.0 },
    -- accent (headings and highlights) and leather (the cover) come from the faction below.
}

-- Each faction binds its book differently: Horde red on brown leather, Alliance blue on
-- navy. accentName is how the Chronicle's key describes the accent colour.
Theme.factions = {
    Horde = {
        accentName = "Red",
        colors = {
            accent = { 0.48, 0.06, 0.03 },
            leather = { 0.29, 0.15, 0.09 },
        },
        crest = "Interface\\TargetingFrame\\UI-PVP-Horde",
    },
    Alliance = {
        accentName = "Blue",
        colors = {
            accent = { 0.07, 0.19, 0.48 },
            leather = { 0.10, 0.14, 0.28 },
        },
        crest = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    },
}

-- Called at login, before any frame is made, so every frame is drawn in the player's colours.
function Theme.Apply(faction)
    local f = Theme.factions[faction]
    for key, color in pairs(f.colors) do
        Theme.colors[key] = color
    end
    Theme.textures.crest = f.crest
    Theme.accentName = f.accentName
end

Theme.textures = {
    page = "Interface\\QuestFrame\\QuestBG",
    border = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    header = "Interface\\DialogFrame\\UI-DialogBox-Header",
    tab = "Interface\\SpellBook\\SpellBook-SkillLineTab",
    crest = nil,  -- the faction's, set by Theme.Apply
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
