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

---

## 参考模组

- BuildingCraft - 官方建造系统参考
- NeatBuilding - Neat 建造系统
- NeatControllerSupport - 手柄支持
