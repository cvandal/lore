local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

local DATE_W = 120

local function Sentence(story, entry)
    return ("Completed at level %d in %s."):format(entry.level or 0, entry.zone or story.zone)
end

UI.RegisterTab({
    key = "journal",
    order = 3,
    title = "Journal",
    icon = Theme.tabIcons.journal,
    Render = function(L)
        local entries = Lore:GetJournalEntries()
        local dated, undated = {}, {}
        for _, item in ipairs(entries) do
            if item.entry.completedAt then
                dated[#dated + 1] = item
            else
                undated[#undated + 1] = item
            end
        end

        L:Text("My Journal", { font = "title", size = 20, justify = "CENTER", gap = 2 })
        local subtitle = #entries == 1 and "One tale told" or (#entries .. " tales told")
        if #dated > 0 then
            subtitle = subtitle .. " since the " .. UI.FormatDay(dated[#dated].entry.completedAt)
        end
        L:Text(subtitle, { size = 11, color = "faded", justify = "CENTER", gap = 8 })
        L:Divider()

        if #entries == 0 then
            L:Text("Your journal is empty. Finish a tale and it will be written here.",
                { size = 13, color = "faded", justify = "CENTER" })
            return
        end

        for _, item in ipairs(dated) do
            local row = L:Row(20, 2)
            UI.RowText(row, item.story.name, { font = "title", size = 15, width = L.width - DATE_W, wrap = false })
            UI.RowText(row, UI.FormatDay(item.entry.completedAt), { anchor = "RIGHT", width = DATE_W,
                justify = "RIGHT", wrap = false, size = 12, color = "crimson" })
            row:SetScript("OnClick", function() UI.ShowStory(item.story) end)
            UI.AddTooltip(row, { item.story.name, "Click to read it again." })
            L:Text(Sentence(item.story, item.entry), { size = 13, color = "faded", gap = 12 })
        end

        if #undated > 0 then
            L:Space(4)
            L:Text("Completed before Lore", { font = "title", size = 14, color = "crimson", gap = 4 })
            for _, item in ipairs(undated) do
                local row = L:Row(20, 1)
                UI.RowText(row, item.story.name, { width = L.width - DATE_W, wrap = false, size = 13 })
                UI.RowText(row, "date unknown", { anchor = "RIGHT", width = DATE_W, justify = "RIGHT",
                    wrap = false, size = 11, color = "faded" })
                row:SetScript("OnClick", function() UI.ShowStory(item.story) end)
                UI.AddTooltip(row, { item.story.name,
                    "You finished this tale before Lore was installed, so the date wasn't recorded.",
                    "Click to read it again." })
            end
        end
    end,
})
