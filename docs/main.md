# Project Zomboid 开发文档

---

## 官方资源

### Wiki & API
- [PZ Wiki - Lua API](https://pzwiki.net/wiki/Lua_(API))
- [PZ Wiki - Joypad](https://pzwiki.net/wiki/Joypad)
- [Project Zomboid Official - Lua API](https://projectzomboid.com/modding/wiki/Lua_API)

### JavaDocs
- [B42 非官方 JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/)
  - [ISBuildIsoEntity](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/_build/entity/ISBuildIsoEntity.html)
  - [IsoCell](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/world/IsoCell.html)
  - [IsoObject](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/IsoObject.html)
  - [IsoWorld](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/iso/world/IsoWorld.html)

---

## 本地文档

### 核心 API
- [Joypad 手柄 API](./joypad.md) - 手柄输入处理、按钮常量、摇杆数据
- [Cell & Building API](./cell-building-api.md) - Cell、GridSquare、Building、ISBuildIsoEntity
- [建造手柄支持方案](./building-joypad-solution.md) - 旋转/移动建筑的解决方案

### 组件结构
- [Neat Crafting 组件结构](./neat-crafting-component-structure.md)
- [Neat Crafting 组件图](./neat-crafting-component-diagram.md)

### 控制器
- [手柄按钮映射](./project-zomboid-controller-buttons.md)
- [控制器循环导航](./controller-cycle-navigation.md)

### 第三方模组扩展点（写联动模组之前先读这两份）
- [橙子社区经济：对外开放的扩展点](../bin2_npc_extension/docs/research/economy-integration-hooks.md)
  - 页面注册表 `OrangeTradingMod.UIPageRegistry.Register`（公开 API）、首页入口包装的官方先例、
    货币 `OrangeTradingModServer.Pay` / `AddCoins`、单机下 `OnClientCommand` 不触发的处理方式
- [Project A-Life / Jeem：招募与生成链路](../bin2_npc_extension/docs/research/jeem-recruit-api.md)
  - `ActorRegistry.create` + `SpawnService.request` + `DecisionLoop.setOrder`（A-Life **没有**原生雇佣机制）、
    `Residents.recruit` / `leaveOne`、防人口回收必须**同时**写 `memory.persistent` 与 `memory.admin.persistent`
- 取证来源（本机只读）：`~/Library/Application Support/Steam/steamapps/workshop/content/108600/{3777900792,3803984183,3806944055}`

---

## 参考模组

- BuildingCraft - 官方建造系统参考
- NeatBuilding - Neat 建造系统
- NeatControllerSupport - 手柄支持
