# 模组代码变更标准作业流程 (Modify SOP)

## 执行步骤

1. **更新 Changelog.txt**
   - 在文件顶部添加 `[ ALERT_CONFIG ]` 配置
   - 使用格式: `[ MM/DD/YYYY ]`
   - 每条变更单独一行，使用 `-` 前缀

2. **更新 mod.info**
   - 更新 `modversion` 版本号
   - 检查 `versionMin` 和 `supports` 版本
   - 检查 `require` 依赖是否正确

3. **更新 workshop.txt**
   - 在上层目录
   - 根据需要更新 `description`
   - 保持 `id` 不变

## Changelog.txt 格式

```
[ ALERT_CONFIG ]
link1 = GitHub = https://github.com/lotosbin/project-zomboid-mods,
link2 = Ko-Fi = https://steamcommunity.com/linkfilter/?u=https://ko-fi.com/lotosbin,
[ ------ ]

[ 03/19/2026 ]
- 添加 ItemName 物品翻译
- 版本升级至 42.15
[ ------ ]

[ 03/15/2026 ]
- 初始版本
[ ------ ]
```

## 版本升级额外步骤

1. 创建新版本目录 (如 `42.15/`)
2. 复制必要文件:
   - `mod.info`, `poster.png`, `icon.png`
   - `media/` 目录
3. 更新 `mod.info` 中的版本号
4. 创建 `Changelog.txt`
5. 执行本 SOP
