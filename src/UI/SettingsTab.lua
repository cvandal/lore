local _, Lore = ...
local UI, Theme = Lore.UI, Lore.Theme

-- Lore's options as checkboxes, a couple of handy tools, and every /lore command. All of it
-- comes from Lore.options and Lore.commands (Core.lua), the same lists /lore uses.

local COMMAND_W = 120

UI.RegisterTab({
    key = "settings",
    order = 4,
    title = "Settings",
    icon = Theme.tabIcons.settings,
    Render = function(L)
        L:Text("Settings", { font = "title", size = 20, justify = "CENTER", gap = 2 })
        L:Text("Saved for this character.", { size = 11, color = "faded", justify = "CENTER", gap = 8 })
        L:Divider()

        L:Text("Options", { font = "title", size = 14, color = "crimson", gap = 8 })
        for _, option in ipairs(Lore.options) do
            L:Check(option.label, option.description, option.get(), function(on)
                Lore:SetOption(option, on)
            end)
        end

        L:Text("Tools", { font = "title", size = 14, color = "crimson", gap = 8 })
        L:Button("Reset window position", 170, 0, function() SlashCmdList.LORE("reset") end)
        L:Space(8)

        L:Text("Slash commands", { font = "title", size = 14, color = "crimson", gap = 4 })
        L:Text("Type these in chat. Each option above has one too.", { size = 12, color = "faded", gap = 8 })
        for _, command in ipairs(Lore.commands) do
            local top = L.y
            L:Text(strtrim("/lore " .. command.command), { size = 13, width = COMMAND_W, wrap = false, gap = 0 })
            L.y = top
            L:Text(command.description, { indent = COMMAND_W, size = 12, color = "faded", gap = 8 })
        end
    end,
})
