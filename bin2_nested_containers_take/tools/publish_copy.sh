#!/usr/bin/env bash
# 把"发布必需"的内容复制到（精确镜像：目标端多余文件会被删除）
# 把"发布必需"的内容复制到 ~/Zomboid/Workshop/bin2_nested_containers_take（真实目录，非软链）。
# 发布内容只包含：workshop.txt / preview.png / changelog.txt / Contents/**
# 结构要求（游戏上传器 SteamWorkshopItem.validateModFolder 的规则）：
#   Contents/ 下只允许 mods/（不能有散落文件）
#   Contents/mods/<ModID>/ 下必须有 common/（全小写！）或版本目录（且版本要落在 [minRequiredVersion, gameVersion]）
#   common/ 里放 mod.info + media/
# 不复制：README.md、tools/、任何 .md/.sh/开发产物、.DS_Store
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="${DST:-$HOME/Zomboid/Workshop/$(basename "$SRC")}"
mkdir -p "$DST"
rsync -a --delete --delete-excluded \
  --include='/workshop.txt' --include='/preview.png' --include='/changelog.txt' \
  --include='/Contents/' --include='/Contents/**' \
  --exclude='.DS_Store' --exclude='*' \
  "$SRC/" "$DST/"
echo "published copy -> $DST"
find "$DST" -type f | sed "s|$DST/||" | sort
