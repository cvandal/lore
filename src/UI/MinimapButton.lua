local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

-- A round button on the minimap's edge: left-click opens Lore, right-click toggles the map
-- pins, drag to move it around the rim (the angle is saved per character).

local SIZE = 31

local function Place(button)
    local angle = math.rad(Lore.db.settings.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor(button)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    Lore.db.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
    Place(button)
end

local function ShowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("Lore", 1, 0.82, 0)
    local story = Lore:GetCurrentStory()
    if story then
        GameTooltip:AddLine(story.name, 1, 1, 1)
    end
    GameTooltip:AddLine("Click to open the book.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click to " .. (Lore.db.settings.pins and "hide" or "show") .. " map pins.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag to move.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function UI.CreateMinimapButton()
    local button = CreateFrame("Button", "LoreMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- The standard minimap-button look: dark disc, icon, gold ring.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(Theme.textures.minimapBackground)
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Theme.tabIcons.current)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetMask(Theme.textures.circleMask)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(Theme.textures.minimapBorder)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture(Theme.textures.minimapHighlight, "ADD")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            SlashCmdList.LORE("pins")
        else
            Lore:Toggle()
        end
        if GameTooltip:IsOwned(button) then ShowTooltip(button) end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Place(button)
    button:SetShown(not Lore.db.settings.minimapHidden)
    UI.minimapButton = button
end

function UI.UpdateMinimapButton()
    if UI.minimapButton then
        UI.minimapButton:SetShown(not Lore.db.settings.minimapHidden)
    end
end
