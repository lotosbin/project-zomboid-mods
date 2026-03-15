# 开发日志

## 2026-03-15

### PZ 42.15 翻译文件格式转换

**问题**: Project Zomboid 42.15 版本更新了国际化本地化系统，从旧的 `.txt` 格式迁移到新的 JSON 格式。需要将模组的中文翻译文件转换为新格式。

**解决方案**:
1. 使用 Playwright 抓取 pzwiki.net/wiki/Translation 页面获取新格式规范
2. 创建转换脚本批量处理翻译文件
3. 为各模组添加 Changelog.txt

**提交记录**:
- `917cc28` - 添加 PZ 42.15 翻译转换脚本
- `d5c9de4` - 翻译文件转换为 JSON 格式 (10个文件)
- `1c499bd` - 为翻译模组添加 Changelog.txt

**修改文件**:
- 新增 10 个 JSON 翻译文件
- 更新 4 个 mod.info 版本
- 新增 5 个 Changelog.txt

### 关键参考
- 翻译格式: https://pzwiki.net/wiki/Translation
- Changelog: https://pzwiki.net/wiki/Mod_Update_and_Alert_System
