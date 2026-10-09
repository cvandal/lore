local _, Lore = ...
local Theme = Lore.Theme

local UI = {}
Lore.UI = UI

-- Tabs register themselves here; MainFrame builds a bookmark for each.
UI.tabs = {}
UI.tabOrder = {}

function UI.RegisterTab(tab)
    UI.tabs[tab.key] = tab
    UI.tabOrder[#UI.tabOrder + 1] = tab
    table.sort(UI.tabOrder, function(a, b) return a.order < b.order end)
end

-- Helpers ----------------------------------------------------------------------

local ROMAN = { { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }

function UI.Roman(n)
    local out = ""
    for _, pair in ipairs(ROMAN) do
        while n >= pair[1] do
            out = out .. pair[2]
            n = n - pair[1]
        end
    end
    return out
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }

-- 1791367000 -> "3rd of October"
function UI.FormatDay(timestamp)
    local d = date("*t", timestamp)
    local suffix = "th"
    if d.day % 100 < 11 or d.day % 100 > 13 then
        suffix = ({ "st", "nd", "rd" })[d.day % 10] or "th"
    end
    return d.day .. suffix .. " of " .. MONTHS[d.month]
end

function UI.StyleText(fs, o)
    fs:SetFont(Theme.fonts[o.font or "body"], o.size or 12, "")
    local c = Theme.colors[o.color or "ink"]
    fs:SetTextColor(c[1], c[2], c[3], o.alpha or 1)
    fs:SetJustifyH(o.justify or "LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(o.wrap ~= false)
    fs:SetShadowOffset(0, 0)
end

function UI.AddTooltip(frame, lines)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, line in ipairs(lines) do
            if i == 1 then
                GameTooltip:AddLine(line, 1, 0.82, 0)
            else
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Pools: tabs redraw from scratch on every refresh, so recycle what they draw.

UI.pools = {}

function UI.NewPool(create, reset)
    local pool = { free = {}, used = {} }
    function pool:Acquire()
        local obj = table.remove(self.free) or create()
        self.used[#self.used + 1] = obj
        obj:Show()
        return obj
    end
    function pool:ReleaseAll()
        for i = #self.used, 1, -1 do
            local obj = self.used[i]
            obj:Hide()
            obj:ClearAllPoints()
            if reset then reset(obj) end
            self.free[#self.free + 1] = obj
            self.used[i] = nil
        end
    end
    UI.pools[#UI.pools + 1] = pool
    return pool
end

function UI.ReleaseAll()
    for _, pool in ipairs(UI.pools) do
        pool:ReleaseAll()
    end
end

function UI.InitPools(content)
    UI.content = content

    UI.textPool = UI.NewPool(function()
        return content:CreateFontString(nil, "OVERLAY")
    end, function(fs)
        fs:SetText("")
    end)

    UI.texturePool = UI.NewPool(function()
        return content:CreateTexture(nil, "ARTWORK")
    end, function(tex)
        tex:SetTexture(nil)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetDesaturated(false)
    end)

    UI.rowPool = UI.NewPool(function()
        local row = CreateFrame("Button", nil, content)
        row:SetHighlightTexture(Theme.textures.rowHighlight, "ADD")
        row:GetHighlightTexture():SetVertexColor(0.56, 0.11, 0.08, 0.35)
        return row
    end, function(row)
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end)

    UI.checkPool = UI.NewPool(function()
        local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        return check
    end, function(check)
        check:SetScript("OnClick", nil)
    end)

    UI.buttonPool = UI.NewPool(function()
        return CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    end, function(button)
        button:SetScript("OnClick", nil)
    end)
end

-- Layout: stacks things top to bottom inside the scrolling page.

local Layout = {}
Layout.__index = Layout

function UI.NewLayout(width)
    return setmetatable({ y = 0, width = width }, Layout)
end

-- o: font ("title" | "body"), size, color, justify, indent, width, gap, wrap
function Layout:Text(text, o)
    o = o or {}
    local fs = UI.textPool:Acquire()
    UI.StyleText(fs, o)
    local x = o.indent or 0
    fs:SetWidth(o.width or (self.width - x))
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", UI.content, "TOPLEFT", x, -self.y)
    self.y = self.y + fs:GetStringHeight() + (o.gap or 4)
    return fs
end

function Layout:Space(height)
    self.y = self.y + height
end

function Layout:Divider(gap)
    local tex = UI.texturePool:Acquire()
    local c = Theme.colors.faded
    tex:SetColorTexture(c[1], c[2], c[3], 0.5)
    tex:SetSize(self.width, 1)
    tex:SetPoint("TOPLEFT", UI.content, "TOPLEFT", 0, -self.y)
    self.y = self.y + 1 + (gap or 8)
    return tex
end

-- A full-width clickable row; place text and icons on it with RowText/RowIcon.
function Layout:Row(height, gap)
    local row = UI.rowPool:Acquire()
    row:SetSize(self.width, height)
    row:SetPoint("TOPLEFT", UI.content, "TOPLEFT", 0, -self.y)
    self.y = self.y + height + (gap or 0)
    return row
end

function Layout:Button(text, width, indent, onClick)
    local button = UI.buttonPool:Acquire()
    button:SetText(text)
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", UI.content, "TOPLEFT", indent or 0, -self.y)
    button:SetScript("OnClick", onClick)
    self.y = self.y + 22 + 6
    return button
end

-- A checkbox with a label and a description underneath; onChange(checked) on click.
function Layout:Check(label, description, checked, onChange)
    local check = UI.checkPool:Acquire()
    check:SetChecked(checked)
    check:SetPoint("TOPLEFT", UI.content, "TOPLEFT", -4, -self.y + 4)
    check:SetScript("OnClick", function(self) onChange(self:GetChecked() and true or false) end)
    local x = 26
    self:Text(label, { indent = x, size = 14, gap = 2 })
    self:Text(description, { indent = x, size = 12, color = "faded", gap = 10 })
    return check
end

-- o: same as Layout:Text plus x, width (defaults to the rest of the row), anchor
function UI.RowText(row, text, o)
    local fs = UI.textPool:Acquire()
    UI.StyleText(fs, o)
    local x = o.x or 0
    fs:SetWidth(o.width or (row:GetWidth() - x))
    fs:SetText(text)
    local anchor = o.anchor or "LEFT"
    fs:SetPoint(anchor, row, anchor, x, 0)
    return fs
end

function UI.RowIcon(row, texture, size, x)
    local tex = UI.texturePool:Acquire()
    tex:SetTexture(texture)
    tex:SetSize(size, size)
    tex:SetPoint("LEFT", row, "LEFT", x, 0)
    return tex
end
