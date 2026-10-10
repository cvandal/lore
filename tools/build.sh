#!/bin/sh
# Rebuilds src/Data/<Faction>Stories.lua from the latest Questie, QuestieDB and pfQuest data.
#   tools/build.sh            update the sources, export, build
#   tools/build.sh --report   also print every story's per-quest scoring
set -e
cd "$(dirname "$0")"

mkdir -p vendor build
for repo in Questie/Questie Questie/QuestieDB shagu/pfQuest; do
    dir="vendor/${repo#*/}"
    if [ -d "$dir" ]; then
        git -C "$dir" pull --quiet --ff-only
    else
        git clone --quiet --depth 1 "https://github.com/$repo.git" "$dir"
    fi
done

# QuestieDB's loaders need PUC Lua 5.1 (LuaJIT can't load its NPC file).
LUA=.lua51/lua-5.1.5/src/lua
if [ ! -x "$LUA" ]; then
    mkdir -p .lua51
    curl -sSL https://www.lua.org/ftp/lua-5.1.5.tar.gz | tar xz -C .lua51
    target=posix; [ "$(uname)" = Darwin ] && target=macosx
    make -C .lua51/lua-5.1.5 "$target" >/dev/null
fi

(cd vendor/QuestieDB && "../../$LUA" ../../export_questiedb.lua ../../build ../pfQuest/db/enUS/quests.lua)
"$LUA" export_blacklist.lua vendor/Questie build/blacklist.json
python3 build_stories.py "$@"
