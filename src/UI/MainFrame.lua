local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

local FRAME_W, FRAME_H = 480, 560
-- The parchment fills everything inside the gold border, whose backdrop insets are 11-12px,
-- so no leather shows between them.
local PAGE_INSET_X, PAGE_TOP, PAGE_BOTTOM = 11, 11, 11
-- Text sits where it always has (46px from the frame's left edge, 44px from the top): the
-- parchment's left edge is darkened, so text starts well clear of it.
local SCROLL_LEFT, SCROLL_RIGHT, SCROLL_TOP, SCROLL_BOTTOM = 35, 39, 33, 27
local CONTENT_W = FRAME_W - 2 * PAGE_INSET_X - SCROLL_LEFT - SCROLL_RIGHT
local TAB_SPACING = 49

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    Lore.db.settings.point = { point, relativePoint, x, y }
end

function UI.ResetPosition()
    if not UI.frame then return end
    UI.frame:ClearAllPoints()
    local saved = Lore.db.settings.point
    if saved then
        UI.frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

-- The spellbook's side tabs, used as bookmarks down the right edge.
local function CreateBookmark(frame, tab, index)
    local button = CreateFrame("CheckButton", nil, frame)
    button:SetSize(32, 32)
    button:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -48 - (index - 1) * TAB_SPACING)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(Theme.textures.tab)
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", -3, 11)

    button:SetNormalTexture(tab.icon)
    button:SetHighlightTexture(Theme.textures.tabHighlight, "ADD")
    button:SetCheckedTexture(Theme.textures.tabChecked)
    button:GetCheckedTexture():SetBlendMode("ADD")

    button:SetScript("OnClick", function() UI.SelectTab(tab.key) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tab.title)
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function CreateMainFrame()
    local f = CreateFrame("Frame", "LoreFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    tinsert(UISpecialFrames, "LoreFrame")  -- Escape closes it

    -- Leather cover inside a gold border.
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = Theme.textures.border,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local leather = Theme.colors.leather
    f:SetBackdropColor(leather[1], leather[2], leather[3], 1)

    local page = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    page:SetTexture(Theme.textures.page)
    page:SetTexCoord(unpack(Theme.pageTexCoord))
    page:SetPoint("TOPLEFT", PAGE_INSET_X, -PAGE_TOP)
    page:SetPoint("BOTTOMRIGHT", -PAGE_INSET_X, PAGE_BOTTOM)
    f.page = page

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture(Theme.textures.header)
    header:SetSize(256, 64)
    header:SetPoint("TOP", 0, 12)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(Theme.fonts.title, 16, "")
    title:SetTextColor(unpack(Theme.colors.gold))
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("Lore")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "LoreScrollFrame", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", SCROLL_LEFT, -SCROLL_TOP)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -SCROLL_RIGHT, SCROLL_BOTTOM)
    f.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)
    UI.InitPools(content)

    f.bookmarks = {}
    for i, tab in ipairs(UI.tabOrder) do
        f.bookmarks[tab.key] = CreateBookmark(f, tab, i)
    end

    f:SetScript("OnShow", function() UI.Refresh() end)
    f:Hide()
    return f
end

function UI.SelectTab(key)
    UI.activeTab = key
    UI.preview = nil  -- a bookmark always opens the tab's own page
    for tabKey, button in pairs(UI.frame.bookmarks) do
        button:SetChecked(tabKey == key)
    end
    UI.frame.scroll:SetVerticalScroll(0)
    UI.Refresh()
end

function UI.Refresh()
    local f = UI.frame
    if not f or not f:IsShown() then return end
    UI.ReleaseAll()
    local layout = UI.NewLayout(CONTENT_W)
    UI.tabs[UI.activeTab].Render(layout)
    UI.content:SetHeight(math.max(layout.y, 1))
end

-- Open the book on a given tab (e.g. /lore settings).
function UI.ShowTab(key)
    if not Lore.isHorde then return Lore:Toggle() end  -- explains why not
    if not UI.frame then
        UI.frame = CreateMainFrame()
        UI.ResetPosition()
    end
    UI.SelectTab(key)
    UI.frame:Show()
end

function UI.Toggle()
    if not UI.frame then
        UI.frame = CreateMainFrame()
        UI.ResetPosition()
    end
    if UI.frame:IsShown() then
        UI.frame:Hide()
        return
    end
    -- Always open on the current tale; OnShow draws it.
    UI.SelectTab("current")
    UI.frame:Show()
end
