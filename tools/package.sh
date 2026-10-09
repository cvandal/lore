#!/bin/sh
# Builds dist/Lore-<version>.zip: the addon alone, in a folder named Lore, ready to unzip
# into Interface/AddOns. Upload it to a GitHub release.
set -e
cd "$(dirname "$0")/.."

version=$(sed -n 's/^## Version: *//p' src/Lore.toc | tr -d '\r')
core=$(sed -n 's/^Lore.version = "\(.*\)"/\1/p' src/Core.lua)
if [ -z "$version" ] || [ "$version" != "$core" ]; then
    echo "error: version in src/Lore.toc ($version) and src/Core.lua ($core) must match" >&2
    exit 1
fi

lua tools/smoke_test.lua >/dev/null || { echo "error: smoke test failed" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/Lore"
# Only what the game loads: the TOC and Lua files.
(cd src && find . -name '*.toc' -o -name '*.lua') | while read -r file; do
    mkdir -p "$stage/Lore/$(dirname "$file")"
    cp "src/$file" "$stage/Lore/$file"
done
cp LICENSE "$stage/Lore/"
chmod -R u=rwX,go=rX "$stage/Lore"

mkdir -p dist
zip_path="$PWD/dist/Lore-$version.zip"
rm -f "$zip_path"
(cd "$stage" && zip -qrX "$zip_path" Lore)
echo "wrote dist/Lore-$version.zip ($(unzip -l "$zip_path" | tail -1 | awk '{print $2}') files)"
