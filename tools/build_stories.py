#!/usr/bin/env python3
"""Builds src/Data/<Faction>Stories.lua from QuestieDB (vanilla / Classic Era) + pfQuest quest text.

The pipeline runs once per faction:
  1. Keep quests a character of that faction can do (drop blacklisted, repeatable, event,
     profession and other non-story quests).
  2. Link quests into a directed graph using their prerequisites.
  3. Score every quest for how story-relevant it is.
  4. Pull stories out of the graph as best-scoring paths, so a hub that fans out into
     unrelated quests becomes several stories and filler side quests are dropped.
  5. Keep the stories that score well enough, rank their importance, and write Lua.

Inputs come from tools/build (see tools/build.sh). Run with --report to print the
scoring breakdown instead of only the summary.
"""
import collections
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
VENDOR = ROOT / "vendor"
DATA = ROOT.parent / "src" / "Data"

# --- Static knowledge ---------------------------------------------------------------

# races and classes: bitmasks of what the faction can play. enemy_classes: the other faction's
# own class, so quests only it can take are dropped. enemy_npc: QuestieDB's faction letter for
# the other side's NPCs, whose quests this faction can't take.
FACTIONS = {
    "Horde": {
        "races": 2 | 16 | 32 | 128,                              # Orc, Undead, Tauren, Troll
        "classes": 1 | 4 | 8 | 16 | 64 | 128 | 256 | 1024,      # every class but Paladin
        "enemy_classes": 2,                                      # Paladin
        "enemy_npc": "A",
    },
    "Alliance": {
        "races": 1 | 4 | 8 | 64,                                 # Human, Dwarf, Night Elf, Gnome
        "classes": 1 | 2 | 4 | 8 | 16 | 128 | 256 | 1024,       # every class but Shaman
        "enemy_classes": 64,                                     # Shaman
        "enemy_npc": "H",
    },
}

# QuestSort categories (negative zoneOrSort) that are never story content.
EXCLUDED_SORTS = {
    -24, -101, -121, -181, -182, -201, -264, -304, -324,  # professions
    -22, -41, -364, -366, -369, -370, -1002, -1003,          # seasonal and holiday events
    -25, -241, -367, -221,                                   # battlegrounds, tournament, reputation grinds, treasure maps
}

# Figures whose involvement marks a quest as part of a faction's (or the world's) story.
LORE_FIGURES = {
    "Thrall", "Cairne Bloodhoof", "Lady Sylvanas Windrunner", "Vol'jin", "Rexxar", "Eitrigg",
    "Varimathras", "Nazgrel", "Neeru Fireblade", "Magatha Grimtotem", "Hamuul Runetotem",
    "Drek'Thar", "High Overlord Saurfang", "Myranda the Hag", "Warlord Goretooth",
    "Tirion Fordring", "Anachronos", "Bethor Iceshard", "Master Apothecary Faranell",
    "Grand Apothecary Putress", "Zor Lonetree", "Mankrik", "Gamon", "Rokhan", "Nekrum Gutchewer",
    "Lord Itharius", "Haleh", "Deathstalker Faerleia", "Archmage Xylem",
    "Lorekeeper Javon", "Lorekeeper Mykos", "Lorekeeper Lydros",
    "Baristolth of the Shifting Sands", "Arch Druid Fandral Staghelm", "Keeper Remulos",
    "Erunak Stonespeaker", "Ralo'shan the Eternal Watcher", "Duke Hydraxis", "Lothos Riftwaker",
    "Highlord Taelan Fordring", "Nara Wildmane",
    # Alliance
    "King Magni Bronzebeard", "Highlord Bolvar Fordragon", "Lady Katrana Prestor", "Varian Wrynn",
    "Tyrande Whisperwind", "Lady Jaina Proudmoore", "High Tinker Mekkatorque", "Archbishop Benedictus",
    "Marshal Windsor", "Reginald Windsor", "Master Mathias Shaw", "Gryan Stoutmantle",
    "Shandris Feathermoon", "Commander Ashlam Valorfist", "Royal Historian Archesonus",
    "Lord Gregor Lescovar", "Vanndar Stormpike", "Prospector Stormpike", "Archmage Tervosh",
}
LORE_WORDS = [
    "thrall", "warchief", "horde", "alliance", "scourge", "lich king", "kel'thuzad", "arthas",
    "burning legion", "legion", "demon", "dragon", "dragonflight", "onyxia", "nefarian",
    "ragnaros", "old god", "c'thun", "titan", "hakkar", "sylvanas", "cairne", "vol'jin",
    "grom", "hellscream", "durotan", "doomhammer", "blackrock", "shadow council", "burning blade",
    "prophecy", "ancient", "artifact", "legend", "history", "ritual", "corruption", "plague",
    "cult of the damned", "argent dawn", "scarlet crusade", "qiraji", "silithid", "kaldorei",
    "night elf", "emerald dream", "nightmare", "elemental", "betray", "traitor", "forsaken",
    "dark iron", "dragonkin", "naaru", "tauren", "earthmother", "spirit", "elder", "lord",
]
# Lore terms only one faction's quests lean on. The Horde's are in LORE_WORDS above.
FACTION_LORE_WORDS = {
    "Horde": [],
    "Alliance": [
        "stormwind", "ironforge", "darnassus", "gnomeregan", "theramore", "lordaeron", "kul tiras",
        "bronzebeard", "magni", "wildhammer", "stormpike", "mekkatorque", "proudmoore", "jaina",
        "tyrande", "bolvar", "wrynn", "defias", "silver hand",
    ],
}
# Story names chosen by hand where the rule-based name (story_name) picks an errand, a report
# or a side character instead of the story, or where a character would see two stories with
# the same name. Keyed by story ID ("q" + first quest ID); each new name is one of the
# chain's own quest titles unless noted.
NAME_OVERRIDES = {
    # Warlock pet quests: all three were "The Binding", and a warlock sees every one.
    "q1506": "Creature of the Void",       # the Voidwalker (level 10)
    "q1507": "Love's Gift",                # the Succubus, Orgrimmar version (level 20)
    "q3001": "Tome of the Cabal",          # the Felhunter (level 30)
    # Errands, deliveries and reports.
    "q460": "Resting in Pieces",           # was "Wand to Bethor", a delivery
    "q1111": "The Rumormonger",            # was "Dream Dust in the Swamp", an errand
    "q2902": "The Battle Plans",           # was "Zukk'ash Report"
    "q4081": "Operation: Death to Angerforge",  # was "Kill On Sight: Dark Iron Dwarves", a bounty
    "q5093": "The Scourge Cauldrons",      # was "Target: Gahrron's Withering", one of four targets
    "q5098": "The Key to Scholomance",     # was "All Along the Watchtowers", the first step
    "q2933": "The Spider God",             # was "Venom to the Undercity", a delivery
    "q1947": "Rituals of Power",           # was "Get the Scoop"
    # Named after a side character or item rather than where the story goes.
    "q5382": "The Lich, Ras Frostwhisper", # was "Doctor Theolen Krastinov, the Butcher"
    "q638": "Trol'kalar",                  # was "Sigil of Strom": the chain is the hunt for the sword
    "q584": "The Fate of Yenniku",         # was "Bloodscalp Clan Heads", a bounty
    "q1104": "Martek the Exiled",          # was "Indurium", an ore
    "q1718": "Cyclonian",                  # was "The Affray": the chain builds to summoning Cyclonian
    "q1000": "Uncovering Past Secrets",    # was "Umber, Archivist"
    "q4001": "The Royal Rescue",           # was "What Is Going On?"
    "q9032": "Lord Valthalak's Amulet",    # was "The Left Piece of...": shortened, covers both halves
    # Alliance. Warlock pets, as above: both were "The Binding".
    "q1685": "Surena Caledon",             # the Voidwalker (level 10): the warlock you hunt for it
    "q1798": "Tome of the Cabal",          # the Felhunter (level 30)
    "q40": "Discover Rolf's Fate",         # was "Cloth and Leather Armor", a delivery
    "q298": "Protecting the Shipment",     # was "Powder to Ironband", a delivery
    "q730": "The Absent Minded Prospector",  # was "Trouble In Darkshore?", the opening errand
    "q373": "The Unsent Letter",           # was "Look to an Old Friend": the letter uncovers the plot
    "q164": "The Shadowy Figure",          # was "Lightforge Iron", an item along the way
    "q468": "Nek'rosh's Gambit",           # was "War Banners", a collection
    "q1448": "Into The Temple of Atal'Hakkar",  # was "Rhapsody's Tale", a side character
    "q5097": "The Key to Scholomance",     # was "All Along the Watchtowers", the first step
    "q8960": "Lord Valthalak's Amulet",    # was "The Left Piece of...", as for the Horde
}

FILLER_PENALTY = 2.5   # "collect/kill 5+ of something ordinary"
FRAMING_WORDS = 3      # lore terms that make a chain's opening quest frame the whole chain
GENERIC_NAME = re.compile(r"^(Return to|Report to|Speak (?:to|with)|Talk to|Seek out|Find |A Letter|Letter to|Message to)", re.I)


def lua_list(value):
    """QuestieDB tables come through as {"1": a, "2": b}; return [a, b]."""
    if not value:
        return []
    if isinstance(value, list):
        return value
    return [value[k] for k in sorted(value, key=int)]


def load():
    data = {name: json.load(open(BUILD / f"vanilla_{name}.json")) for name in ("quest", "npc", "item", "object")}
    data["text"] = json.load(open(BUILD / "pfquest_text.json"))
    data["blacklist"] = set(json.load(open(BUILD / "blacklist.json")))
    return data


def load_zone_names():
    names = {}
    pf = (VENDOR / "pfQuest/db/enUS/zones.lua").read_text(encoding="utf-8")
    for zid, name in re.findall(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)"', pf):
        names[int(zid)] = name.replace("\\'", "'")
    # Questie's own area IDs (10000+, e.g. dungeon wings) only exist in its lookup.
    lookup = (VENDOR / "Questie/Localization/lookups/lookupZones.lua").read_text(encoding="utf-8")
    for zid, name in re.findall(r'\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"', lookup):
        zid = int(zid)
        if zid > 10000 and zid not in names:
            names[zid] = name
    return names


def load_instances():
    """AreaId -> (name, kind, entrance) for dungeons and raids, including their alternative
    area IDs. entrance is (parentAreaId, x, y) or None."""
    raids = {"Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj",
             "Temple of Ahn'Qiraj", "Naxxramas"}
    # Only the main table: the overrides after it are for later expansions.
    text = (VENDOR / "QuestieDB/support/Zones/dungeons.lua").read_text(encoding="utf-8")
    text = text[:text.index("\n}\n")]
    instances = {}
    pattern = r'\[(\d+)\] = \{"([^"]+)",(\{[\d,]*\}|nil),\d+,\{\{(\d+),\s*([\d.]+),\s*([\d.]+)\}'
    for zid, name, alts, parent, x, y in re.findall(pattern, text):
        kind = "raid" if name in raids else "dungeon"
        if name in ("Deeprun Tram", "Hall of Legends", "Champions' Hall"):
            continue
        entrance = (int(parent), float(x), float(y))
        for area in [int(zid)] + [int(a) for a in re.findall(r"\d+", alts)]:
            instances[area] = (name, kind, entrance)
    return instances


def load_ui_maps():
    """AreaId -> uiMapID (the map IDs the game's map API uses)."""
    text = (VENDOR / "QuestieDB/support/Zones/areaIdToUiMapId.lua").read_text(encoding="utf-8")
    maps = {}
    for area, ui in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", text):
        maps.setdefault(int(area), int(ui))  # the override table comes first and wins
    return maps


def load_forever_maps():
    """uiMapID -> (scale_x, offset_x, scale_y, offset_y) for the zone maps WoW Forever redrew
    (Mulgore, Eastern Plaguelands, Redridge Mountains, Stormwind City). Lore's quest data is
    vanilla, but it runs on the Forever client, so positions on those maps are converted:
    forever = vanilla * scale + offset, in 0-100 map percentages."""
    conversion = json.load(open(VENDOR / "QuestieDB/data/Forever/conversion.json"))
    maps = {}
    for t in conversion["geometry"]["transforms"]:
        if t["changed"]:
            c = t["coefficients"]
            maps[t["ui_map_id"]] = (c["scale_x"], c["offset_x"], c["scale_y"], c["offset_y"])
    return maps


# --- Filtering ------------------------------------------------------------------------

def enemy_only_giver(q, npcs, faction):
    starters = lua_list((q.get("2") or {}).get("1"))
    factions = [(npcs.get(str(n)) or {}).get("13") for n in starters]
    return bool(factions) and all(f == faction["enemy_npc"] for f in factions)


def is_obtainable(qid, q, blacklist, npcs, faction):
    """In the game and open to some character of the faction. Required quests are resolved
    against this, so a chain never loses a step the player must do, even a repeatable one."""
    name = q.get("1") or ""
    races = q.get("6") or 0
    classes = q.get("7") or 0
    if enemy_only_giver(q, npcs, faction) or int(qid) in blacklist or not name:
        return False
    if races and not (races & faction["races"]):
        return False
    if classes and not (classes & ~faction["enemy_classes"]):
        return False
    return not re.search(r"UNUSED|<NYI>|\[PH\]|\bTEST\b|DEPRECATED|<TXT>|zzOLD", name)


def is_candidate(qid, q, blacklist, npcs, faction):
    """Obtainable, and the kind of quest that can be story."""
    if not is_obtainable(qid, q, blacklist, npcs, faction):
        return False
    flags = q.get("24") or 0
    sort = q.get("17") or 0
    if flags & 1:  # repeatable (holiday quests are removed by the blacklist and sorts)
        return False
    return not (sort in EXCLUDED_SORTS or q.get("18") or q.get("35"))  # professions


# --- Scoring ----------------------------------------------------------------------------

class Scorer:
    def __init__(self, data, instances, faction_name):
        self.q, self.npc, self.item, self.obj, self.text = data["quest"], data["npc"], data["item"], data["object"], data["text"]
        self.instances = instances
        self.words = LORE_WORDS + FACTION_LORE_WORDS[faction_name]
        self.figure_ids = {nid for nid, n in self.npc.items() if n.get("1") in LORE_FIGURES}

    def spawn_count(self, npc_id):
        n = self.npc.get(str(npc_id))
        if not n:
            return 99
        return sum(len(lua_list(coords)) for coords in (n.get("7") or {}).values())

    def is_named(self, npc_id):
        """A unique or elite foe: a story target rather than one of many."""
        n = self.npc.get(str(npc_id))
        if not n:
            return False
        rank = n.get("6") or 0
        return rank in (1, 2, 3, 4) and self.spawn_count(npc_id) <= 3 or self.spawn_count(npc_id) <= 1

    def npc_zones(self, npc_id):
        n = self.npc.get(str(npc_id)) or {}
        return {int(z) for z in (n.get("7") or {})} | ({n["9"]} if n.get("9") else set())

    def givers(self, q):
        started = q.get("2") or {}
        return [str(i) for i in lua_list(started.get("1"))]

    def enders(self, q):
        finished = q.get("3") or {}
        return [str(i) for i in lua_list(finished.get("1"))]

    def objective_text(self, qid, q):
        pf = self.text.get(qid) or {}
        return pf.get("O") or " ".join(lua_list(q.get("8")))

    def description(self, qid):
        return (self.text.get(qid) or {}).get("D") or ""

    def instance_of(self, qid, q):
        """Dungeon or raid this quest sends you into, if any."""
        sort = q.get("17") or 0
        if sort in self.instances:
            return self.instances[sort]
        # A target counts only when it lives exclusively inside instances; plenty of
        # open-world creatures also have a stray copy in some dungeon.
        objectives = q.get("10") or {}
        targets = [lua_list(e)[0] for e in lua_list(objectives.get("1"))]
        for entry in lua_list(objectives.get("3")):
            item = self.item.get(str(lua_list(entry)[0])) or {}
            droppers = lua_list(item.get("2"))
            if droppers and not item.get("3") and all(self.npc_zones(d) and self.npc_zones(d) <= set(self.instances) for d in droppers):
                targets.append(droppers[0])
        for target in targets:
            zones = self.npc_zones(target)
            if zones and zones <= set(self.instances):
                return self.instances[sorted(zones)[0]]
        return None

    def lore_words(self, qid):
        """The LORE_WORDS that appear in a quest's description and objective."""
        text = (self.description(qid) + " " + self.objective_text(qid, self.q[qid])).lower()
        return {w for w in self.words if re.search(r"\b" + re.escape(w) + r"\b", text)}

    def is_filler(self, qid):
        """Whether score() applied the filler penalty to this quest."""
        return any(w.startswith("filler") for w in self.score(qid)[1])

    def score(self, qid):
        """Returns (score, reasons) for one quest."""
        q = self.q[qid]
        score, why = 0.0, []
        desc = self.description(qid)
        objective = self.objective_text(qid, q)
        objectives = q.get("10") or {}

        people = set(self.givers(q)) | set(self.enders(q))
        if people & self.figure_ids:
            who = sorted(self.npc[p]["1"] for p in people & self.figure_ids)
            score += 3.0
            why.append("lore figure: " + ", ".join(who))

        words = self.lore_words(qid)
        if words:
            score += min(len(words) * 0.4, 2.0)
            why.append("lore words: " + ", ".join(sorted(words)[:5]))
        if len(desc) > 450:
            score += 0.5
            why.append("long text")

        named_kills = [lua_list(e)[0] for e in lua_list(objectives.get("1")) if self.is_named(lua_list(e)[0])]
        generic_kills = [lua_list(e)[0] for e in lua_list(objectives.get("1")) if not self.is_named(lua_list(e)[0])]
        if named_kills:
            score += 2.0
            why.append("named foe")

        counts = [int(n) for n in re.findall(r"\b(\d+)\b", objective) if 2 <= int(n) <= 50]
        many = max(counts) if counts else 0
        item_objectives = lua_list(objectives.get("3"))
        generic_loot = 0
        for entry in item_objectives:
            item = self.item.get(str(lua_list(entry)[0])) or {}
            droppers = lua_list(item.get("2"))
            if item.get("3") or (droppers and not any(self.is_named(d) for d in droppers)):
                generic_loot += 1
            elif droppers:
                score += 1.0
                why.append("loot from named foe")
        if len(item_objectives) >= 3:
            score -= 1.5
            why.append("component collection")
        if many >= 5 and (generic_kills or generic_loot or lua_list(objectives.get("2"))):
            score -= FILLER_PENALTY
            why.append(f"filler: {many}x")

        if not objectives and not q.get("9"):
            score += 0.5
            why.append("errand / dialogue")

        instance = self.instance_of(qid, q)
        if instance:
            score += 1.5 if instance[1] == "dungeon" else 2.0
            why.append(f"{instance[1]}: {instance[0]}")

        if GENERIC_NAME.search(q.get("1") or ""):
            score -= 0.5
        return score, why


# --- Graph and story extraction ------------------------------------------------------

def build_graph(quests, ids):
    """Directed edges prerequisite -> quest. Class-specific and general quests aren't joined,
    so a class letter doesn't glue every class chain into one story."""
    succ, pred = collections.defaultdict(set), collections.defaultdict(set)

    def link(a, b):
        if a in ids and b in ids and a != b and (quests[a].get("7") or 0) == (quests[b].get("7") or 0):
            succ[a].add(b)
            pred[b].add(a)

    for qid in ids:
        q = quests[qid]
        for pre in lua_list(q.get("13")) + lua_list(q.get("12")):
            link(str(pre), qid)
        if q.get("22"):
            link(qid, str(q["22"]))
        for crumb_target in [q.get("27")] if q.get("27") else []:
            link(qid, str(crumb_target))
    return succ, pred


def topo_order(nodes, succ, pred):
    indeg = {n: len(pred[n] & nodes) for n in nodes}
    ready = sorted((n for n in nodes if indeg[n] == 0), key=int)
    order = []
    while ready:
        n = ready.pop(0)
        order.append(n)
        for m in sorted(succ[n] & nodes, key=int):
            indeg[m] -= 1
            if indeg[m] == 0:
                ready.append(m)
    # Any cycle leftovers go last; QuestieDB data occasionally loops.
    order += sorted(nodes - set(order), key=int)
    return order


def best_path(nodes, succ, pred, weight):
    """Highest-weight path through the DAG restricted to `nodes`."""
    order = topo_order(nodes, succ, pred)
    best, back = {}, {}
    for n in order:
        # Sorted, so ties go to the lowest quest ID on every run (set order is randomised per
        # run, which would change story IDs, and journal entries are keyed by them).
        prev = sorted((p for p in pred[n] & nodes if p in best), key=int)
        p = max(prev, key=lambda x: best[x], default=None)
        if p is not None and best[p] > 0:
            best[n], back[n] = best[p] + weight[n], p
        else:
            best[n], back[n] = weight[n], None
    end = max(order, key=lambda n: best[n])
    path = [end]
    while back[path[-1]] is not None:
        path.append(back[path[-1]])
    return list(reversed(path)), best[end]


def components(ids, succ, pred):
    seen, comps = set(), []
    for start in sorted(ids, key=int):
        if start in seen:
            continue
        stack, comp = [start], set()
        seen.add(start)
        while stack:
            x = stack.pop()
            comp.add(x)
            for y in (succ[x] | pred[x]) & ids:
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        comps.append(comp)
    return comps




def extract_stories(ids, succ, pred, weight):
    """Peel best paths off each component, so a hub that fans out into unrelated quests
    becomes several stories. Strong side quests hanging off a path (e.g. parallel trials)
    are folded into it; everything else is filler and dropped."""
    stories = []
    for comp in components(ids, succ, pred):
        remaining = set(comp)
        while remaining:
            path, total = best_path(remaining, succ, pred, weight)
            remaining -= set(path)
            if total <= 0:
                break
            stories.append({"path": path, "extra": []})
    on_path = {qid: i for i, story in enumerate(stories) for qid in story["path"]}
    for qid in sorted(ids, key=int):
        if qid in on_path or weight[qid] < 2.5:
            continue
        neighbours = [on_path[n] for n in sorted(succ[qid] | pred[qid], key=int) if n in on_path]
        if neighbours:
            stories[neighbours[0]]["extra"].append(qid)
    return stories


def add_prerequisites(chosen, quests, obtainable, weight):
    """Best paths skip side branches, but some of those are required: Redemption needs Demon
    Dogs, Blood Tinged Skies and Carrion Grubbage all done (preQuestGroup), and a quest with
    preQuestSingle needs one of its list. Pull every required quest into the story that needs
    it, unless another kept story already has it: then the chapter records it under `after`,
    and the book says which tale to finish first. Required quests come from every quest a
    player of the faction can get, not just story candidates (the Royal Rescue's escort is repeatable,
    but you still have to do it). A quest belongs to one story only: when two stories need
    the same one, the first (in level order) takes it and the other points at it. Runs after
    selection and keeps each story's ID, so it never changes which stories are kept or
    breaks journal entries."""
    owner = {}
    for story in chosen:
        for qid in story["raw"]["members"]:
            owner[qid] = story
    for story in chosen:
        members = set(story["raw"]["members"])
        after = collections.defaultdict(set)
        todo = sorted(members, key=int)
        while todo:
            m = todo.pop()
            q = quests[m]
            needed = [str(p) for p in lua_list(q.get("12")) if str(p) in obtainable]
            options = sorted((str(p) for p in lua_list(q.get("13")) if str(p) in obtainable),
                             key=lambda p: (-weight.get(p, 0), int(p)))
            if options and not any(p in members for p in options):
                # The list is often one quest's class or race versions: take them all, so
                # the chapter stays open to everyone who could do one of them.
                name = quests[options[0]].get("1")
                needed += [p for p in options if quests[p].get("1") == name]
            for p in needed:
                if p in members:
                    continue
                if p in owner and owner[p] is not story:
                    after[m].add(p)
                    continue
                members.add(p)
                owner[p] = story
                todo.append(p)
        story["raw"] = {"path": sorted(members, key=int), "extra": [], "after": after, "id": story["id"]}


# --- Assembly ------------------------------------------------------------------------

BRACKET_QUOTA = 16     # general stories kept per 10-level bracket
ALWAYS_KEEP = 30.0     # stories this strong are kept even past the quota
MIN_SCORE = 8.0
CLASS_MIN_SCORE = 8.0


def mask_to_ids(mask):
    """Bitmask -> sorted IDs (bit i is ID i+1). The addon gets plain ID lists rather than
    masks, so it needs no bit library."""
    return [bit + 1 for bit in range(32) if mask & (1 << bit)]


class Assembler:
    def __init__(self, data, scorer, zones, scores, faction):
        self.q, self.npc, self.obj, self.text = data["quest"], data["npc"], data["object"], data["text"]
        self.scorer, self.zones, self.scores, self.faction = scorer, zones, scores, faction
        self.ui_maps = load_ui_maps()
        self.forever_maps = load_forever_maps()
        self.npc_names = {n.get("1") for n in self.npc.values() if n.get("1")}
        self.rewards = collections.defaultdict(list)  # questID -> reward item names
        for item in data["item"].values():
            for qid in lua_list(item.get("6")):
                self.rewards[str(qid)].append(item.get("1"))

    def place(self, kind, entity_id):
        """Where an NPC or object stands, as {name, area, map, x, y, inside}. Open-world
        spawns win; someone inside a dungeon is placed at its entrance, with `inside` naming
        the dungeon. `map` is the uiMapID map pins need, coordinates are 0-100."""
        table = self.npc if kind == "npc" else self.obj
        e = table.get(str(entity_id)) or {}
        spawns = e.get("7" if kind == "npc" else "4") or {}
        best = None
        for zone, coords in spawns.items():
            coords = lua_list(coords)
            if not coords:
                continue
            xy = lua_list(coords[0])
            if len(xy) < 2:
                continue
            if xy[0] < 0 and int(zone) not in self.scorer.instances:
                continue  # no known position; inside an instance the entrance stands in
            candidate = (int(zone), xy[0], xy[1])
            if best is None or (best[0] in self.scorer.instances and int(zone) not in self.scorer.instances):
                best = candidate
        spot = {"name": e.get("1")}
        if best is None:
            return spot
        area, x, y = best
        if area in self.scorer.instances:
            spot["inside"] = self.scorer.instances[area][0]
            area, x, y = self.scorer.instances[area][2]
        spot["area"] = area
        ui_map = self.ui_maps.get(area)
        if ui_map:
            if ui_map in self.forever_maps:
                sx, ox, sy, oy = self.forever_maps[ui_map]
                x, y = x * sx + ox, y * sy + oy
            spot.update(map=ui_map, x=round(x, 1), y=round(y, 1))
        return spot

    def person(self, q, field):
        entry = q.get(field) or {}
        for kind, index in (("npc", "1"), ("object", "2")):
            ids = lua_list(entry.get(index))
            if kind == "npc":
                # Class quests list trainers of both factions; send players to their own.
                ours = [i for i in ids if (self.npc.get(str(i)) or {}).get("13") != self.faction["enemy_npc"]]
                ids = ours or ids
            if ids:
                return self.place(kind, ids[0])
        return {}

    def level_range(self, members):
        lows, highs = [], []
        for m in members:
            q = self.q[m]
            level = q.get("5") or 0
            required = q.get("4") or 0
            if level > 0:
                highs.append(level)
            if required > 0 or level > 0:
                lows.append(required or level)
        low = max(1, min(lows) if lows else 1)
        high = min(60, max(highs) if highs else low)
        return low, max(low, high)

    def story_name(self, members):
        """Best title in the chain: a high-scoring quest that isn't an errand, a delivery or
        just an NPC's name. Ties go to the later quest (the climax)."""
        def title_score(m):
            name = self.q[m].get("1") or ""
            score = self.scores[m][0]
            if GENERIC_NAME.search(name) or re.match(r"(Back to|Delivery to|Going|Bring|Return the|Further Instructions|Deliver)", name):
                score -= 3
            if name in self.npc_names:
                score -= 2
            return score
        pick = max(reversed(members), key=title_score)
        name = re.sub(r"(\.\.\.|,? Take \d+)$", "", self.q[pick].get("1"))
        # "KILL ON SIGHT: Dark Iron Dwarves" -> "Kill On Sight: Dark Iron Dwarves"
        return re.sub(r"\b([A-Z])([A-Z]+)\b", lambda m: m.group(1) + m.group(2).lower(), name)

    def zone_name(self, area):
        return self.zones.get(area) if area else None

    def quest_entry(self, qid):
        q = self.q[qid]
        pf = self.text.get(qid) or {}
        giver = self.person(q, "2")
        ender = self.person(q, "3")
        sort = q.get("17") or 0
        zone = (giver.get("inside") or self.zone_name(giver.get("area"))
                or self.zone_name(sort if sort > 0 else None) or "")
        entry = {
            "ids": [int(qid)],
            "name": q.get("1"),
            "level": q.get("5") or 0,
            "zone": zone,
            "summary": pf.get("D") or "",
            "objective": pf.get("O") or " ".join(lua_list(q.get("8"))),
        }
        for prefix, spot in (("giver", giver), ("ender", ender)):
            entry[prefix] = spot.get("name")
            entry[prefix + "Map"] = spot.get("map")
            entry[prefix + "X"] = spot.get("x")
            entry[prefix + "Y"] = spot.get("y")
            entry[prefix + "Inside"] = spot.get("inside")
        return entry

    def eligibility(self, members):
        """Race and class masks for the whole story: every chapter must be doable. Same-name
        quests are one chapter's race or class versions, so their masks combine (any one
        will do); then the chapters' masks intersect. 0 means anyone."""
        def combine(field, everyone):
            by_name = {}
            for m in members:
                mask = self.q[m].get(field) or 0
                name = self.q[m].get("1")
                mask = everyone if mask == 0 else mask & everyone
                by_name[name] = mask if name not in by_name else by_name[name] | mask
            result = everyone
            for mask in by_name.values():
                result &= mask
            return 0 if result == everyone else result or None  # None: nobody can do it all
        return combine("6", self.faction["races"]), combine("7", self.faction["classes"])

    def story(self, raw):
        members = topo_order(set(raw["path"] + raw["extra"]), self.scorer.succ, self.scorer.pred)
        quest_scores = [self.scores[m][0] for m in members]
        low, high = self.level_range(members)
        instance_kinds = {self.scorer.instance_of(m, self.q[m]) for m in members} - {None}
        races, classes = self.eligibility(members)
        if races is None or classes is None:
            return None
        if classes:
            kind = "class"
        elif any(inst[1] == "raid" for inst in instance_kinds):
            kind = "raid"
        elif instance_kinds:
            kind = "dungeon"
        else:
            kind = "world"
        # Same-name quests that aren't linked to each other are alternatives (class or race
        # versions): one chapter, completed by doing any of them. Sequential parts keep their rows.
        entries, by_name = [], {}
        for m in members:
            name = self.q[m].get("1")
            group = by_name.get(name)
            linked = group and any(str(i) in (self.scorer.succ[m] | self.scorer.pred[m]) for i in group["ids"])
            if group and not linked:
                group["ids"].append(int(m))
            else:
                by_name[name] = self.quest_entry(m)
                entries.append(by_name[name])
            after = raw.get("after", {}).get(m)
            if after:
                by_name[name]["after"] = sorted(set(by_name[name].get("after", [])) | {int(p) for p in after})
        score = sum(max(self.scores[str(i)][0] for i in e["ids"]) for e in entries) + 2.4 * math.log2(len(entries))
        # Scores are per quest, but a chain can be more than its parts: when the opening quest
        # is steeped in the story (Sylvanas wants a plague to destroy Arthas's Scourge), the
        # errands that follow from the same quest giver serve that story, so they aren't filler.
        framed = len(self.scorer.lore_words(members[0])) >= FRAMING_WORDS
        if framed:
            opener_givers = set(self.scorer.givers(self.q[members[0]]))
            for m in members:
                if set(self.scorer.givers(self.q[m])) & opener_givers and self.scorer.is_filler(m):
                    score += FILLER_PENALTY
        # The same reward from three or more quests is a gear-upgrade ladder, not a story.
        reward_counts = collections.Counter(r for m in members for r in set(self.rewards[m]))
        if reward_counts and max(reward_counts.values()) >= 3:
            score *= 0.5
        story_id = raw.get("id") or "q" + members[0]
        return {
            "id": story_id,
            "name": NAME_OVERRIDES.get(story_id) or self.story_name(members),
            "zone": entries[0]["zone"],
            "minLevel": low,
            "maxLevel": high,
            "kind": kind,
            "races": mask_to_ids(races) if races else [],
            "classes": mask_to_ids(classes) if classes else [],
            "score": score,
            "framed": framed,
            "quests": entries,
        }


def select(stories):
    """Per-bracket quotas so low levels aren't crowded out by long level-60 chains."""
    chosen = []
    general = [s for s in stories if s["kind"] != "class"]
    for bracket in range(6):
        pool = sorted((s for s in general if min(5, (s["minLevel"] - 1) // 10) == bracket),
                      key=lambda s: s["score"], reverse=True)
        keep = [s for i, s in enumerate(pool)
                if s["score"] >= MIN_SCORE and (i < BRACKET_QUOTA or s["score"] >= ALWAYS_KEEP)]
        for rank, s in enumerate(keep):
            pct = rank / max(len(keep), 1)
            s["importance"] = 3 if pct < 0.25 else 2 if pct < 0.6 else 1
        chosen += keep
    for s in stories:
        if s["kind"] == "class" and s["score"] >= CLASS_MIN_SCORE:
            s["importance"] = 2
            chosen.append(s)
    chosen.sort(key=lambda s: (s["minLevel"], -s["importance"], -s["score"]))
    return chosen


# --- Lua output ------------------------------------------------------------------------

def lua_value(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n") + '"'
    if isinstance(value, list):
        return "{ " + ", ".join(lua_value(v) for v in value) + " }"
    raise TypeError(value)


def write_lua(stories, path, faction_name):
    lines = [
        "-- GENERATED by tools/build_stories.py - do not edit by hand.",
        "-- Quest data: QuestieDB (vanilla / Classic Era). Quest text: pfQuest (MIT). Text (c) Blizzard Entertainment.",
        "local _, Lore = ...",
        "",
        f"Lore.storyData.{faction_name} = {{",
    ]
    story_keys = ["id", "name", "zone", "minLevel", "maxLevel", "importance", "kind", "races", "classes"]
    quest_keys = ["ids", "name", "level", "zone", "giver", "giverMap", "giverX", "giverY", "giverInside",
                  "ender", "enderMap", "enderX", "enderY", "enderInside", "after", "objective", "summary"]
    for s in stories:
        lines.append("    {")
        for k in story_keys:
            if s.get(k) not in (None, []):
                lines.append(f"        {k} = {lua_value(s[k])},")
        lines.append("        quests = {")
        for q in s["quests"]:
            fields = ", ".join(f"{k} = {lua_value(q[k])}" for k in quest_keys if q.get(k) not in (None, "", []))
            lines.append(f"            {{ {fields} }},")
        lines.append("        },")
        lines.append("    },")
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# --- Main -----------------------------------------------------------------------------

def check_unique(stories):
    """Journal entries are keyed by story ID and the addon maps each quest to one story, so
    both must be unique. Stop the build rather than write data that mixes stories up."""
    ids = collections.Counter(s["id"] for s in stories)
    quest_ids = collections.Counter(i for s in stories for q in s["quests"] for i in q["ids"])
    errors = [f"story ID {k} used {n} times" for k, n in ids.items() if n > 1]
    errors += [f"quest {k} is in {n} stories" for k, n in quest_ids.items() if n > 1]
    if errors:
        sys.exit("error: " + "; ".join(sorted(errors)))


def warn_duplicate_names(stories):
    """Warn when one character could see two stories with the same name: same name, and
    their race and class lists overlap (an empty list means everyone)."""
    def overlaps(a, b):
        return not a or not b or bool(set(a) & set(b))
    for i, a in enumerate(stories):
        for b in stories[i + 1:]:
            if a["name"] == b["name"] and overlaps(a["races"], b["races"]) and overlaps(a["classes"], b["classes"]):
                print(f"warning: duplicate story name {a['name']!r}: {a['id']} and {b['id']} (add a NAME_OVERRIDES entry)")


def build_faction(faction_name, data, zones, instances, report):
    """Runs the whole pipeline for one faction and writes its data file. Returns the IDs of
    the stories kept."""
    faction = FACTIONS[faction_name]
    quests = data["quest"]
    scorer = Scorer(data, instances, faction_name)
    out = DATA / f"{faction_name}Stories.lua"

    obtainable = {qid for qid, q in quests.items() if is_obtainable(qid, q, data["blacklist"], data["npc"], faction)}
    ids = {qid for qid in obtainable if is_candidate(qid, quests[qid], data["blacklist"], data["npc"], faction)}
    scores = {qid: scorer.score(qid) for qid in obtainable}
    # Every quest keeps a small positive weight so chains still connect through plain links.
    weight = {qid: max(scores[qid][0], -1.0) + 1.0 for qid in ids}
    # Edges cover every obtainable quest so required steps sort into place; story extraction
    # only ever walks the candidates.
    scorer.succ, scorer.pred = build_graph(quests, obtainable)
    raw = extract_stories(ids, scorer.succ, scorer.pred, weight)

    assembler = Assembler(data, scorer, zones, scores, faction)
    candidates = []
    for r in raw:
        story = assembler.story(r)
        if story is None or len(story["quests"]) == 1 and story["score"] < 4.5:
            continue
        story["raw"] = {"members": r["path"] + r["extra"]}
        candidates.append(story)
    chosen = select(candidates)
    add_prerequisites(chosen, quests, obtainable, weight)
    rebuilt = []
    for old in chosen:
        story = assembler.story(old["raw"])
        if story is None:
            print(f"warning: {old['name']!r} ({old['id']}): no race and class can do every chapter, dropped")
            continue
        story["importance"] = old["importance"]
        rebuilt.append(story)
    chosen = sorted(rebuilt, key=lambda s: (s["minLevel"], -s["importance"], -s["score"]))
    check_unique(chosen)
    warn_duplicate_names(chosen)
    write_lua(chosen, out, faction_name)

    print(f"{faction_name}: candidate quests: {len(ids)}  candidate stories: {len(candidates)}  kept: {len(chosen)}")
    print(f"wrote {out} ({out.stat().st_size // 1024} KB)")
    by_kind = collections.Counter(s["kind"] for s in chosen)
    print("by kind:", dict(by_kind))
    for s in chosen:
        if report or s["kind"] != "class":
            tag = "*" * s["importance"]
            extra = f" [{','.join(str(c) for c in s['classes'])}]" if s["classes"] else ""
            framed = " (framed: its errands aren't filler)" if report and s["framed"] else ""
            print(f"  {s['minLevel']:2d}-{s['maxLevel']:2d} {tag:3s} {s['score']:5.1f} {len(s['quests']):2d}q  {s['name']}  ({s['zone']}){extra}{framed}")
            if report:
                for q in s["quests"]:
                    sc, why = scores[str(q["ids"][0])]
                    print(f"           {sc:5.1f} {q['name']} [{q['ids'][0]}] {'; '.join(why)}")
    print()
    return {s["id"] for s in chosen}


def main():
    report = "--report" in sys.argv
    data = load()
    zones = load_zone_names()
    instances = load_instances()
    kept = set()
    for faction_name in FACTIONS:
        kept |= build_faction(faction_name, data, zones, instances, report)
    unused = set(NAME_OVERRIDES) - kept
    if unused:
        print("warning: NAME_OVERRIDES for stories no longer kept:", ", ".join(sorted(unused)))


if __name__ == "__main__":
    main()
