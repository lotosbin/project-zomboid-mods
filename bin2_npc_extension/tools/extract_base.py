#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把「口味模组」里的**公共逻辑**机械地抽到 Bin2NPCExtensionBase。

为什么用脚本而不是手抄
--------------------
抽取的难点不是"写新的公共层"，而是**证明公共层与抽取前的代码逐字等价**。
手抄一遍，等价性就只能靠人眼；这个脚本把等价性变成可复核的产物：

  * 每个中性文件的正文**原样搬运**（只做缩进 + 工厂包装），
  * 所有改动都是脚本里显式列出的**字面量替换**，每条必须**恰好命中一次**，
    命中 0 次或多次 -> 拒绝执行、不改任何文件（照 skill 的"特征串唯一命中"纪律），
  * 跑完打印每个文件的差异报告（去包装后的旧正文 vs 新正文），
    让"只改了这些"这句话有证据。

抽取后公共层文件就是**新的事实来源**，人可以直接改它；本脚本的 `--check` 只在"抽取当时"有意义
（一旦有人手改了公共层，它就应当报差异，那不是缺陷）。因此：

  * **迁移当时的等价性证据** = 本脚本的差异报告（记录在 docs/develop_log_*.md）；
  * **永久的等价性保证** = 两套离线测试（39 条断言）在抽取前后逐条通过 ——
    这才是"行为没变"的持续守卫，文本 diff 只是迁移那一次的快照。

公共层"不含任何口味身份"这条持续不变量由 tools/check_base.py 守。

用法：
    python3 tools/extract_base.py            # 复核（默认）：只比对，不写盘
    python3 tools/extract_base.py --write     # 从 Bin2NPCExtension 重新生成公共层
    python3 tools/extract_base.py --verbose
"""

from __future__ import annotations

import argparse
import difflib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ITEM_DIR = os.path.dirname(HERE)
MODS_DIR = os.path.join(ITEM_DIR, "Contents", "mods")
SOURCE_MOD = "Bin2NPCExtension"          # 抽取的源：橙子社区经济口味
BASE_MOD = "Bin2NPCExtensionBase"
VERSION_DIR = "42.21"
CORE = "Bin2NPCExtensionCore"            # 公共层的命名空间（不含任何口味身份）

# ---------------------------------------------------------------------------
# 每个中性文件：源路径 -> 公共层文件名 + 显式字面量替换表
# 顺序 = 依赖顺序（Profile.lua 按这个顺序实例化）
# ---------------------------------------------------------------------------

# --- Config.lua -------------------------------------------------------------
CONFIG = [
    (
        "    Bin2NPCExtension :: Config（shared，客户端与服务端共用）",
        "    Bin2NPCExtensionCore :: Config（公共层工厂）",
    ),
    (
        "Bin2NPCExtension = Bin2NPCExtension or {}\n"
        "\n"
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
    (
        "-- 翻译工具挂到同一张表上（Text 不依赖 Config，没有循环 require）\n"
        'require "Bin2NPCExtension/Text"\n'
        "\n"
        'Config.MODULE = "Bin2NPCExtension"       -- 必须等于 mod.info 的 id\n'
        'Config.VERSION = "0.2.3"\n'
        'Config.TAG = "Bin2NPCExtension.Contracts.v1"   -- 我们自己的 ModData 存档表\n'
        "\n"
        "--[[\n"
        '    同一个工坊物品里的"另一个口味"的 mod id（可选）。\n'
        "\n"
        "    这两个模组可以同时启用、名册各自独立，但**同一个 A-Life NPC 不能被两边同时雇走**，\n"
        "    所以 Service.hireExisting 会顺手读一眼兄弟模组的存档（只读、拿不到就当没有）。\n"
        "    生成器会把这一行在变体里翻成对方的 id（见 tools/fork_variant.py 的 PRE_SUBS_PATCHES）。\n"
        "]]\n"
        'Config.SIBLING_MODULE = "Bin2NPCExtensionYese"\n'
        "Config.SCHEMA = 1\n",
        "--[[\n"
        "    身份字段（MODULE / VERSION / TAG / TABLE / SIBLING_MODULE / TEXT_PREFIX / PLAYER_PREFIX /\n"
        "    FLOW_ITEM / ECONOMY_*）由 Namespace.lua 按口味的 spec 注入 —— 公共层里不留任何字面量，\n"
        "    这条不变量由 tools/check_base.py 守着。\n"
        "\n"
        "    SIBLING_MODULE 是\"同一个工坊物品里的另一个口味\"的 mod id（可选）：两个口味可以同时\n"
        "    启用、名册各自独立，但**同一个 A-Life NPC 不能被两边同时雇走**，所以 Service.hireExisting\n"
        "    会顺手读一眼兄弟模组的存档（只读、拿不到就当没有）。\n"
        "]]\n"
        "Config.SCHEMA = 1\n",
    ),
    (
        "-- 沙盒选项表名\n"
        'Config.TABLE = "Bin2NPCExtension"\n',
        "-- 沙盒选项表名由口味注入（每个口味一套独立选项，互不覆盖）\n",
    ),
    (
        "-- 客户端每次进入世界最多尝试注册 UI 的次数（橙子经济可能比我们晚加载）",
        "-- 客户端每次进入世界最多尝试注册 UI 的次数（经济模组可能比我们晚加载）",
    ),
    (
        "    依赖探测：橙子社区经济（硬依赖，但探测写法保持软性）",
        "    依赖探测：经济模组（硬依赖，但探测写法保持软性；全局名由口味注入）",
    ),
    (
        '    local mod = rawget(_G, "OrangeTradingMod")',
        "    local mod = rawget(_G, Config.ECONOMY_GLOBAL)",
    ),
    (
        '    local server = rawget(_G, "OrangeTradingModServer")',
        "    local server = rawget(_G, Config.ECONOMY_SERVER_GLOBAL)",
    ),
]

# --- Text.lua ---------------------------------------------------------------
TEXT = [
    (
        "    Bin2NPCExtension :: Text（shared）\n"
        "\n"
        "    我们自己的翻译命名空间：IGUI_Bin2NPCExtension_*，文件在\n"
        "    media/lua/shared/Translate/<LANG>/IG_UI.json。\n"
        "\n"
        "    为什么不复用橙子经济的 OrangeTradingMod.Text()：\n"
        '    那个函数会把所有不以 "IGUI_OrangeTradingMod_" 开头的键**强行加前缀**，\n'
        '    我们没法在不污染对方命名空间的前提下使用它。所以这里自己做同样的"取不到就退化"逻辑。',
        "    Bin2NPCExtensionCore :: Text（公共层工厂）\n"
        "\n"
        "    翻译命名空间由口味注入（NS.TEXT_PREFIX = IGUI_<mod id>_），文案在**各口味自己的**\n"
        "    media/lua/shared/Translate/<LANG>/IG_UI.json 里。\n"
        "\n"
        "    为什么不复用上游经济模组的 Text()：\n"
        "    那个函数会把所有不以它自己前缀开头的键**强行加前缀**，我们没法在不污染对方命名空间的\n"
        '    前提下使用它。所以这里自己做同样的"取不到就退化"逻辑。',
    ),
    (
        "Bin2NPCExtension = Bin2NPCExtension or {}\n"
        "local Text = {}\n"
        "Bin2NPCExtension.Text = Text\n"
        "\n"
        'Text.PREFIX = "IGUI_Bin2NPCExtension_"',
        "local Config = NS\n"
        "\n"
        "local Text = {}\n"
        "Config.Text = Text\n"
        "\n"
        "-- 前缀由口味注入：IGUI_<mod id>_，两个口味的键空间互不干扰\n"
        "Text.PREFIX = Config.TEXT_PREFIX",
    ),
    (
        "    所以这里按 select('#') 分流，与橙子经济的做法一致。",
        "    所以这里按 select('#') 分流，与上游经济模组的做法一致。",
    ),
]

# --- Contracts.lua ----------------------------------------------------------
CONTRACTS = [
    (
        "    Bin2NPCExtension :: Contracts（shared，纯数据逻辑）",
        "    Bin2NPCExtensionCore :: Contracts（公共层工厂，纯数据逻辑）",
    ),
    (
        'Bin2NPCExtension = Bin2NPCExtension or {}\n'
        'require "Bin2NPCExtension/Config"\n'
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
]

# --- Store.lua --------------------------------------------------------------
STORE = [
    (
        "    Bin2NPCExtension :: Store（server）",
        "    Bin2NPCExtensionCore :: Store（公共层工厂）",
    ),
    (
        "    为什么不借橙子经济的 DataBucket：\n"
        '    它只把自己的白名单键当"权威桶"（runtime_core.lua 的 fixedBucketSet），\n'
        "    第三方键会退化成普通 ModData —— 那还不如我们直接用 ModData，少一层间接。",
        "    为什么不借上游经济模组的 DataBucket：\n"
        '    它只把自己的白名单键当"权威桶"（fixedBucketSet），第三方键会退化成普通 ModData\n'
        "    —— 那还不如我们直接用 ModData，少一层间接。证据见 docs/research/economy-integration-hooks.md。",
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Contracts"\n'
        "\n"
        "local Config = Bin2NPCExtension\n"
        "local Contracts = Config.Contracts\n",
        "local Config = NS\n"
        "local Contracts = Config.Contracts\n",
    ),
    (
        'Store.PLAYER_PREFIX = "Bin2NPCExtensionPlayer_"',
        "-- 玩家键前缀由口味注入：两个口味各自独立记账，同一个玩家在两边的契约不串档\n"
        "Store.PLAYER_PREFIX = Config.PLAYER_PREFIX",
    ),
]

# --- Economy.lua ------------------------------------------------------------
ECONOMY = [
    (
        "    Bin2NPCExtension :: Economy（server，橙子社区经济适配层）",
        "    Bin2NPCExtensionCore :: Economy（公共层工厂，经济模组适配层）",
    ),
    (
        "    钱的唯一通道：OrangeTradingModServer.Pay / AddCoins。",
        "    钱的唯一通道：经济模组服务端表的 Pay / AddCoins（全局名由口味注入）。",
    ),
    (
        "    这些函数都是橙子经济 server/runtime_core.lua 里导出的全局函数（见\n"
        "    docs/research/economy-integration-hooks.md），我们只读不写它的存档形状。",
        "    这些函数都是上游经济模组服务端导出的全局函数（每个口味的证据报告见它自己\n"
        "    Profile.lua 旁的 docs/research/*-integration-hooks.md），我们只读不写它的存档形状。",
    ),
    (
        'require "Bin2NPCExtension/Config"\n\nlocal Config = Bin2NPCExtension\n',
        "local Config = NS\n",
    ),
    (
        "    扣款。橙子经济的 Pay 是服务端权威的",
        "    扣款。上游经济模组的 Pay 是服务端权威的",
    ),
    (
        '        "Bin2NPCExtension.contract", 1, price, extra)',
        "        Config.FLOW_ITEM, 1, price, extra)",
    ),
]

# --- Alife.lua --------------------------------------------------------------
ALIFE = [
    (
        "    Bin2NPCExtension :: Alife（server，A-Life 适配层）",
        "    Bin2NPCExtensionCore :: Alife（公共层工厂，A-Life 适配层）",
    ),
    (
        'require "Bin2NPCExtension/Config"\n\nlocal Config = Bin2NPCExtension\n',
        "local Config = NS\n",
    ),
]

# --- Jimmy.lua --------------------------------------------------------------
JIMMY = [
    (
        "    Bin2NPCExtension :: Jimmy（server，Jeem Extension 适配层）",
        "    Bin2NPCExtensionCore :: Jimmy（公共层工厂，Jeem Extension 适配层）",
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Alife"\n'
        "\n"
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
]

# --- Service.lua ------------------------------------------------------------
SERVICE = [
    (
        "    Bin2NPCExtension :: Service（server，命令处理 = 唯一改状态的地方）",
        "    Bin2NPCExtensionCore :: Service（公共层工厂，命令处理 = 唯一改状态的地方）",
    ),
    (
        '        module = "Bin2NPCExtension"（我们自己的 mod id，不能借用 A-Life / Jeem 的）',
        "        module = Config.MODULE（我们自己的 mod id，不能借用 A-Life / Jeem 的）",
    ),
    (
        '        sendServerCommand(player, "Bin2NPCExtension", "State", payload)',
        '        sendServerCommand(player, Config.MODULE, "State", payload)',
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Contracts"\n'
        'require "Bin2NPCExtension/Text"\n'
        'require "Bin2NPCExtension/Store"\n'
        'require "Bin2NPCExtension/Alife"\n'
        'require "Bin2NPCExtension/Jimmy"\n'
        'require "Bin2NPCExtension/Economy"\n'
        "\n"
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
    (
        "    自带限速与去重：橙子经济的 action_request_guard 是白名单制（只护它自己的命令），",
        "    自带限速与去重：上游经济模组的 action_request_guard 是白名单制（只护它自己的命令），",
    ),
]

# --- Maintain.lua -----------------------------------------------------------
MAINTAIN = [
    (
        "    Bin2NPCExtension :: Maintain（server，周期维护）",
        "    Bin2NPCExtensionCore :: Maintain（公共层工厂，周期维护）",
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Contracts"\n'
        'require "Bin2NPCExtension/Store"\n'
        'require "Bin2NPCExtension/Alife"\n'
        'require "Bin2NPCExtension/Jimmy"\n'
        'require "Bin2NPCExtension/Economy"\n'
        'require "Bin2NPCExtension/Service"\n'
        "\n"
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
]

# --- Net.lua ----------------------------------------------------------------
NET = [
    (
        "    Bin2NPCExtension :: Net（client）",
        "    Bin2NPCExtensionCore :: Net（公共层工厂）",
    ),
    (
        "    我们自己的网络层，与橙子经济的 module 完全分离：\n"
        '        * 联机客户端：sendClientCommand(player, "Bin2NPCExtension", cmd, args)\n'
        "        * 单机 / 主机：直接调服务端 Service.dispatch（同一进程，server 文件在单机也会加载）\n"
        '        * 回包：服务端 sendServerCommand(player, "Bin2NPCExtension", "State", payload)\n'
        "          单机没有回包，直接吃 dispatch 的返回值。",
        "    我们自己的网络层，与上游经济模组的 module 完全分离：\n"
        "        * 联机客户端：sendClientCommand(player, Config.MODULE, cmd, args)\n"
        "        * 单机 / 主机：直接调服务端 Service.dispatch（同一进程，server 文件在单机也会加载）\n"
        '        * 回包：服务端 sendServerCommand(player, Config.MODULE, "State", payload)\n'
        "          单机没有回包，直接吃 dispatch 的返回值。",
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Text"\n'
        "\n"
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
    (
        "--[[\n"
        "    幂等 + 防\"Reset Lua\"重入。\n"
        "\n"
        "    本文件可能在两条路径上各跑一次（引擎 LoadDirBase 自动加载 / 被其它文件 require），\n"
        "    而它在文件体里注册了 Events.OnServerCommand —— 重复注册会让每条回包被处理两次。\n"
        "\n"
        "    判据用 **Events 表的身份**而不是一个布尔量：同一张 Events 表 = 同一次 Lua 会话（跳过）；\n"
        "    换了一张 Events 表 = 引擎重置过 Lua（必须重新注册，否则功能会静默失效）。\n"
        "    这是本项目\"通用工程约定 §4 防 Reset Lua 重入\"的落地方式（见\n"
        "    bin2_ProjectALifeNPCs_extensions/docs/roadmap.md 阶段 4）。\n"
        "]]\n"
        "if Config.NetEvents == Events and Config.Net ~= nil then return Config.Net end\n"
        "Config.NetEvents = Events\n",
        "--[[\n"
        "    幂等 + 防\"Reset Lua\"重入。\n"
        "\n"
        "    事件注册搬到了 Net.install()（由口味的 client 层文件调用）：本文件在公共层是\n"
        "    shared，加载时只定义工厂，不能有副作用。\n"
        "\n"
        "    判据用 **Events 表的身份**而不是一个布尔量：同一张 Events 表 = 同一次 Lua 会话（跳过）；\n"
        "    换了一张 Events 表 = 引擎重置过 Lua（必须重新注册，否则功能会静默失效）。\n"
        "    这是本项目\"通用工程约定 §4 防 Reset Lua 重入\"的落地方式（见\n"
        "    bin2_ProjectALifeNPCs_extensions/docs/roadmap.md 阶段 4）。\n"
        "]]\n"
        "if Config.NetEvents == Events and Config.Net ~= nil then return Config.Net end\n"
        "Config.NetEvents = Events\n",
    ),
    (
        "    操作结果反馈：优先借用橙子经济的电台提示，退到 HaloNote。",
        "    操作结果反馈：优先借用上游经济模组的电台提示，退到 HaloNote。",
    ),
    (
        "-- 联机下的回包\n"
        "local function onServerCommand(module, command, args)\n"
        "    if module ~= Config.MODULE then return end\n"
        '    if tostring(command) ~= "State" then return end\n'
        "    Net.apply(args)\n"
        "end\n"
        "\n"
        "if Events ~= nil and Events.OnServerCommand ~= nil then\n"
        "    Events.OnServerCommand.Add(onServerCommand)\n"
        "end\n"
        "\n"
        "return Net",
        "-- 联机下的回包\n"
        "local function onServerCommand(module, command, args)\n"
        "    if module ~= Config.MODULE then return end\n"
        '    if tostring(command) ~= "State" then return end\n'
        "    Net.apply(args)\n"
        "end\n"
        "\n"
        "--[[\n"
        "    接线：由**口味的 client 层文件**调用。公共层文件是 shared，加载时机比 client 层早，\n"
        "    在文件体里注册就等于「所有口味共享一次注册」，所以注册必须是显式的。\n"
        "]]\n"
        "function Net.install()\n"
        "    if Events ~= nil and Events.OnServerCommand ~= nil then\n"
        "        Events.OnServerCommand.Add(onServerCommand)\n"
        "    end\n"
        "    return Net\n"
        "end\n"
        "\n"
        "return Net",
    ),
]

# --- server/Bootstrap.lua -> ServerBootstrap.lua ----------------------------
SERVER_BOOTSTRAP = [
    (
        "    Bin2NPCExtension :: Bootstrap（server）\n"
        "\n"
        "    事件接线：\n"
        "      * OnClientCommand   —— 收客户端命令（module 必须是我们自己的 mod id）\n"
        "      * OnGameStart / OnServerStarted —— 进档恢复指令 + 打日志自检\n"
        "      * EveryOneMinute    —— 日薪结算\n"
        "      * OnTick            —— 岗位补派 / 指令重下 / 阵亡清理（内部节流到 ~1 秒）\n"
        "\n"
        "    注意：纯单机下 server 文件**也会加载**（引擎会 LoadDirBase(\"server\")），\n"
        "    但 OnClientCommand 不会触发 —— 单机路径由客户端 Net 层直接调用 Service.dispatch。",
        "    Bin2NPCExtensionCore :: ServerBootstrap（公共层工厂）\n"
        "\n"
        "    事件接线（全部在 ServerBootstrap.install() 里，由**口味的 server 层文件**触发）：\n"
        "      * OnClientCommand   —— 收客户端命令（module 必须是我们自己的 mod id）\n"
        "      * OnGameStart / OnServerStarted —— 进档恢复指令 + 打日志自检\n"
        "      * EveryOneMinute    —— 日薪结算\n"
        "      * OnTick            —— 岗位补派 / 指令重下 / 阵亡清理（内部节流到 ~1 秒）\n"
        "\n"
        "    为什么不在文件体里注册：公共层文件是 shared，**客户端也会加载**（纯单机下 server 层\n"
        "    也有加载，但多人客户端不加载 server 层）。接线放进 install() 之后，\"只在哪里注册\"\n"
        "    这件事仍然由口味的层文件决定，与抽取前完全一致。\n"
        "\n"
        "    注意：纯单机下 server 文件**也会加载**（引擎会 LoadDirBase(\"server\")），\n"
        "    但 OnClientCommand 不会触发 —— 单机路径由客户端 Net 层直接调用 Service.dispatch。",
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Store"\n'
        'require "Bin2NPCExtension/Alife"\n'
        'require "Bin2NPCExtension/Jimmy"\n'
        'require "Bin2NPCExtension/Economy"\n'
        'require "Bin2NPCExtension/Service"\n'
        'require "Bin2NPCExtension/Maintain"\n'
        "\n"
        "local Config = Bin2NPCExtension\n",
        "local Config = NS\n",
    ),
    (
        '        Config.warn("Orange Community Economy (OrangeCommunityEconomy) is missing; '
        'the recruit page stays hidden")',
        '        Config.warn(Config.ECONOMY_NAME .. " (" .. Config.ECONOMY_MOD_ID\n'
        '            .. ") is missing; the recruit page stays hidden")',
    ),
    (
        "if Events ~= nil then\n"
        "    if Events.OnClientCommand ~= nil then Events.OnClientCommand.Add(onClientCommand) end\n"
        "    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onWorldReady) end\n"
        "    if Events.OnServerStarted ~= nil then Events.OnServerStarted.Add(onWorldReady) end\n"
        "    if Events.EveryOneMinute ~= nil then Events.EveryOneMinute.Add(onEveryMinute) end\n"
        "    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end\n"
        "end\n"
        "\n"
        "-- 文件加载即尝试一次（A-Life 的 shared 文件在启动期就建好 ModCompat，所以这一发通常就够）\n"
        "Bootstrap.reportCompat()\n"
        "\n"
        "return Bootstrap",
        "--[[\n"
        "    接线。由口味的 server 层文件调用（见该口味的 server/Bootstrap.lua）：\n"
        "        require(\"Bin2NPCExtensionCore/ServerBootstrap\")(NS).install()\n"
        "]]\n"
        "function Bootstrap.install()\n"
        "    if Events ~= nil then\n"
        "        if Events.OnClientCommand ~= nil then Events.OnClientCommand.Add(onClientCommand) end\n"
        "        if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onWorldReady) end\n"
        "        if Events.OnServerStarted ~= nil then Events.OnServerStarted.Add(onWorldReady) end\n"
        "        if Events.EveryOneMinute ~= nil then Events.EveryOneMinute.Add(onEveryMinute) end\n"
        "        if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end\n"
        "    end\n"
        "\n"
        "    -- 装完即尝试一次（A-Life 的 shared 文件在启动期就建好 ModCompat，所以这一发通常就够）\n"
        "    Bootstrap.reportCompat()\n"
        "    return Bootstrap\n"
        "end\n"
        "\n"
        "return Bootstrap",
    ),
]

# --- client/Bootstrap.lua -> ClientBootstrap.lua ---------------------------
CLIENT_BOOTSTRAP = [
    (
        "    Bin2NPCExtension :: Bootstrap（client）\n"
        "\n"
        "    客户端只做三件事：\n"
        "      1. 把招募页注册进橙子社区经济并装上首页入口（对方可能比我们晚就绪 → 重试到成功为止）；\n"
        "      2. 挂一个热键（Ctrl+Alt+N）—— 对方全库没有任何按键绑定，不会冲突；\n"
        "      3. 进世界时打一行自检日志（依赖状态 + 是否接上了 UI）。",
        "    Bin2NPCExtensionCore :: ClientBootstrap（公共层工厂）\n"
        "\n"
        "    客户端只做三件事（全部由 ClientBootstrap.install() 触发，口味的 client 层文件负责调用）：\n"
        "      1. 把招募页注册进经济模组并装上入口（对方可能比我们晚就绪 → 重试到成功为止）；\n"
        "      2. 挂一个热键（Ctrl+Alt+N）—— 对方全库没有任何按键绑定，不会冲突；\n"
        "      3. 进世界时打一行自检日志（依赖状态 + 是否接上了 UI）。\n"
        "\n"
        "    页面的**容器**（ui/Page.lua、ui/Entry.lua）是口味自己实现的：不同经济模组的 UI 原语\n"
        "    不一样，这一层没法共用。这里只依赖它的两个契约入口：Config.Entry.install / .open\n"
        "    与 Config.RecruitPage.ID，且都按\"可能还没就绪\"探测。",
    ),
    (
        'require "Bin2NPCExtension/Config"\n'
        'require "Bin2NPCExtension/Net"\n'
        'require "Bin2NPCExtension/ui/Entry"\n'
        "\n"
        "local Config = Bin2NPCExtension\n"
        "local Entry = Config.Entry\n",
        "local Config = NS\n",
    ),
    (
        "function Bootstrap.tryInstall()\n"
        "    if installed then return true end\n"
        "    local ok, result = pcall(Entry.install)\n",
        "function Bootstrap.tryInstall()\n"
        "    if installed then return true end\n"
        "    -- Entry 是口味的 client 层文件，可能还没加载（或这个口味根本没实现）\n"
        "    local Entry = Config.Entry\n"
        "    if Entry == nil or type(Entry.install) ~= \"function\" then return false end\n"
        "    local ok, result = pcall(Entry.install)\n",
    ),
    (
        "    if Entry.open(number) then\n"
        '        Config.log("recruit panel opened via hotkey")\n'
        "    else\n"
        '        Config.warn("hotkey pressed but the Orange economy UI is unavailable")\n'
        "    end",
        "    local Entry = Config.Entry\n"
        "    if Entry ~= nil and type(Entry.open) == \"function\" and Entry.open(number) then\n"
        '        Config.log("recruit panel opened via hotkey")\n'
        "    else\n"
        '        Config.warn("hotkey pressed but the economy mod UI is unavailable")\n'
        "    end",
    ),
    (
        '            .. " attempts; is OrangeCommunityEconomy enabled?")',
        '            .. " attempts; is " .. Config.ECONOMY_MOD_ID .. " enabled?")',
    ),
    (
        "if Events ~= nil then\n"
        "    if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onGameStart) end\n"
        "    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end\n"
        "    if Events.OnKeyPressed ~= nil then Events.OnKeyPressed.Add(onKeyPressed) end\n"
        "end\n"
        "\n"
        "-- 文件加载时先试一次（我们的 mod 声明了 loadModAfter，通常这时对方已经就绪）\n"
        "Bootstrap.tryInstall()\n"
        "\n"
        "return Bootstrap",
        "--[[\n"
        "    接线。由口味的 client 层文件调用（见该口味的 client/Bootstrap.lua）：\n"
        "        require(\"Bin2NPCExtensionCore/ClientBootstrap\")(NS).install()\n"
        "\n"
        "    调用前口味的 client 层必须已经把 ui/Entry（连带 ui/Page）加载好。\n"
        "]]\n"
        "function Bootstrap.install()\n"
        "    -- 回包通道属于客户端接线，跟着一起装（Net 本身由 Profile 在 shared 层实例化）\n"
        "    local Net = Config.Net\n"
        "    if Net ~= nil and type(Net.install) == \"function\" then Net.install() end\n"
        "\n"
        "    if Events ~= nil then\n"
        "        if Events.OnGameStart ~= nil then Events.OnGameStart.Add(onGameStart) end\n"
        "        if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end\n"
        "        if Events.OnKeyPressed ~= nil then Events.OnKeyPressed.Add(onKeyPressed) end\n"
        "    end\n"
        "\n"
        "    -- 装完先试一次（我们的 mod 声明了 loadModAfter，通常这时对方已经就绪）\n"
        "    Bootstrap.tryInstall()\n"
        "    return Bootstrap\n"
        "end\n"
        "\n"
        "return Bootstrap",
    ),
]

FILES = [
    ("Config.lua", "shared/Bin2NPCExtension/Config.lua", CONFIG),
    ("Text.lua", "shared/Bin2NPCExtension/Text.lua", TEXT),
    ("Contracts.lua", "shared/Bin2NPCExtension/Contracts.lua", CONTRACTS),
    ("Store.lua", "server/Bin2NPCExtension/Store.lua", STORE),
    ("Economy.lua", "server/Bin2NPCExtension/Economy.lua", ECONOMY),
    ("Alife.lua", "server/Bin2NPCExtension/Alife.lua", ALIFE),
    ("Jimmy.lua", "server/Bin2NPCExtension/Jimmy.lua", JIMMY),
    ("Service.lua", "server/Bin2NPCExtension/Service.lua", SERVICE),
    ("Maintain.lua", "server/Bin2NPCExtension/Maintain.lua", MAINTAIN),
    ("Net.lua", "client/Bin2NPCExtension/Net.lua", NET),
    ("ServerBootstrap.lua", "server/Bin2NPCExtension/Bootstrap.lua", SERVER_BOOTSTRAP),
    ("ClientBootstrap.lua", "client/Bin2NPCExtension/Bootstrap.lua", CLIENT_BOOTSTRAP),
]

WRAP_HEADER = """--[[
    公共层工厂（由 tools/extract_base.py 从口味模组机械搬移而来；来源表见该脚本的 FILES）。

    本文件**不含任何口味身份**（mod id / 存档表名 / 翻译前缀 / 经济模组全局名），
    加载时只定义工厂、不产生副作用。口味的 Profile.lua 这样实例化它：

        <NS>.{name} = require("{core}/{name}")(<NS>)

    参数 NS 是该口味的命名空间表（见 {core}/Namespace.lua）；接线（Events 注册）
    由口味的 client/server 层文件调用工厂返回对象的 install() 触发。
    这条"公共层零身份"的不变量由 tools/check_base.py 守着。
]]
"""


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def read_origin(rel_origin, ref):
    """读抽取前的源文件。给了 --from-git 就从那个提交里读，否则读工作区。

    有了这个，本次抽取的差异报告可以**永久复现**：
        python3 tools/extract_base.py --from-git <抽取前的提交> --verbose
    （Base 之后被手改过的话它当然会报差异 —— 那是预期的，此时公共层才是事实来源。）
    """
    rel = os.path.join("Contents", "mods", SOURCE_MOD, VERSION_DIR, "media", "lua", rel_origin)
    if not ref:
        return read(os.path.join(ITEM_DIR, rel)), os.path.join(ITEM_DIR, rel)
    # git show 的路径要以**仓库根**为基准（本模块是仓库里的一个子目录）
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ITEM_DIR,
                         capture_output=True, text=True).stdout.strip()
    repo_rel = os.path.relpath(os.path.join(ITEM_DIR, rel), top)
    result = subprocess.run(["git", "show", "%s:%s" % (ref, repo_rel)],
                            cwd=top, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("git show %s:%s 失败：%s" % (ref, repo_rel, result.stderr.strip()))
    return result.stdout, "%s:%s" % (ref, repo_rel)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def apply_edits(name, origin, text, edits):
    """逐条替换；命中次数不等于 1 就抛错（不写任何文件）。"""
    problems = []
    for old, new in edits:
        count = text.count(old)
        if count != 1:
            problems.append(
                "  [%s] 期望命中 1 次，实际 %d 次：%r" % (name, count, old[:90]))
            continue
        text = text.replace(old, new)
    if problems:
        raise SystemExit(
            "字面量替换未唯一命中（源文件 %s 可能已经改过；先看下面的原文再改脚本）：\n%s"
            % (origin, "\n".join(problems)))
    return text


def indent(body):
    out = []
    for line in body.split("\n"):
        out.append(("    " + line) if line.strip() else line)
    return "\n".join(out)


def build(verbose, ref):
    results = {}
    for base_name, origin, edits in FILES:
        original, origin_path = read_origin(origin, ref)
        edited = apply_edits(base_name, origin, original, edits)
        if edited.lstrip().startswith("--[[\n    公共层工厂"):
            raise SystemExit("%s: 看起来已经是包装过的公共层文件，拒绝二次包装" % origin)
        key = base_name[:-len(".lua")]
        header = WRAP_HEADER.format(
            origin="%s/%s" % (SOURCE_MOD, origin), ns=SOURCE_MOD, name=key, core=CORE)
        wrapped = (
            "Bin2NPCExtensionCore = Bin2NPCExtensionCore or {}\n"
            "\n"
            + header
            + "local function factory(NS)\n"
            + indent(edited.rstrip("\n"))
            + "\nend\n\n"
            + "Bin2NPCExtensionCore.%s = factory\n" % key
            + "return factory\n"
        )
        results[base_name] = (origin_path, original, edited, wrapped)
        if verbose:
            print("  包装 %-22s <- %s" % (base_name, origin))
    return results


def report(results, verbose):
    """打印"去包装后的旧正文 vs 新正文"的差异 —— 这就是抽取的等价性证据。"""
    total_changed = 0
    for base_name in sorted(results):
        origin_path, original, edited, wrapped = results[base_name]
        diff = [line for line in difflib.unified_diff(
            original.rstrip("\n").split("\n"), edited.rstrip("\n").split("\n"),
            fromfile="抽取前 " + os.path.basename(origin_path),
            tofile="抽取后 " + base_name, lineterm="", n=0)]
        changed = [line for line in diff if line[:1] in "+-" and line[:3] not in ("+++", "---")]
        total_changed += len(changed)
        print("%-22s 改动行 %d" % (base_name, len(changed)))
        if verbose:
            for line in diff:
                print("      " + line)
    print("合计改动行（不含包装）：%d" % total_changed)


def main():
    parser = argparse.ArgumentParser(description="把公共逻辑抽到 Bin2NPCExtensionBase")
    parser.add_argument("--write", action="store_true", help="写盘（默认只复核）")
    parser.add_argument("--verbose", action="store_true", help="逐行打印差异")
    parser.add_argument("--from-git", metavar="REF", default=None,
                        help="从该提交读抽取前的源文件（复核历史抽取时用）")
    args = parser.parse_args()

    print("源  : Contents/mods/%s/%s" % (SOURCE_MOD, VERSION_DIR))
    print("公共: Contents/mods/%s/%s/media/lua/shared/%s/" % (BASE_MOD, VERSION_DIR, CORE))
    print()
    results = build(args.verbose, args.from_git)
    report(results, True)

    dest_root = os.path.join(MODS_DIR, BASE_MOD, VERSION_DIR, "media", "lua", "shared", CORE)
    if not args.write:
        problems = []
        for base_name, (_, _, _, wrapped) in results.items():
            path = os.path.join(dest_root, base_name)
            if not os.path.isfile(path):
                problems.append("缺失：" + base_name)
            elif read(path) != wrapped:
                problems.append("内容不一致（有人手改了公共层？）：" + base_name)
        print()
        if problems:
            print("公共层与「从口味机械搬移」的结果不一致（%d 处）：" % len(problems))
            for line in problems:
                print("  " + line)
            return 1
        print("公共层 %d 个文件与机械搬移结果一致。" % len(results))
        return 0

    for base_name, (_, _, _, wrapped) in results.items():
        write(os.path.join(dest_root, base_name), wrapped)
    print()
    print("已写入 %d 个公共层文件到 %s" % (len(results), dest_root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
