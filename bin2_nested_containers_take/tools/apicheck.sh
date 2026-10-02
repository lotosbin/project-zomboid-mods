#!/usr/bin/env bash
set -euo pipefail
ITEM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PZ_JAVA_DIR="${PZ_JAVA_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java}"
GAME_LUA="$PZ_JAVA_DIR/media/lua"
[[ -d "$GAME_LUA" ]] || { echo "ERROR: 找不到游戏的 media/lua" >&2; exit 1; }
APIS=( "ISBaseTimedAction" "ISInventoryTransferAction" "ISTimedActionQueue" "addAfter"
       "getItemById" "IsInventoryContainer" "getInventory" "getContainingItem" "getContainer"
       "getType" "getWorldItem" "getParent" "getID" "getName" "isInCharacterInventory"
       "getCapacityWeight" "getMaxWeight" "getActualWeight" "isWearingAwkwardGloves" "isTimedActionInstant"
       "Remove" "AddItem" "sendRemoveItemFromContainer" "sendAddItemToContainer" "sendReplaceItemInContainer"
       "isItemAllowed" "hasRoomFor" "isRemoveItemAllowed"
       "getContainerPosition" "getFreezerPosition" "setActionAnim" "setAnimVariable" "playSound" "getEmitter" )
echo "== NestedContainersTake API 契约自检 =="
miss=0
for api in "${APIS[@]}"; do
  hit="$(grep -rl --include="*.lua" -F "$api" "$GAME_LUA" 2>/dev/null | head -1 || true)"
  if [[ -n "$hit" ]]; then printf "  %-30s OK   %s\n" "$api" "${hit#"$GAME_LUA"/}"; else printf "  %-30s MISS\n" "$api"; miss=$((miss+1)); fi
done
[[ "$miss" -eq 0 ]] && echo "== 全部命中（${#APIS[@]} 项）==" || { echo "== $miss 项 MISS ==" >&2; exit 1; }
