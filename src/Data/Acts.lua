local _, Lore = ...

-- The Chronicle groups stories into acts by the level they start at. Each faction's first
-- act is its own; Lore:LoadStories picks the player's.
local function Acts(first)
    return {
        { name = first, minLevel = 1, maxLevel = 19 },
        { name = "Act II - A Wider World", minLevel = 20, maxLevel = 39 },
        { name = "Act III - Shadow and Flame", minLevel = 40, maxLevel = 60 },
    }
end

Lore.actsByFaction = {
    Horde = Acts("Act I - Blood and Honor"),
    Alliance = Acts("Act I - Light and Valor"),
}
