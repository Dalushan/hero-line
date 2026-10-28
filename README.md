# TD Hero Defense · Godot 4.7

塔防 + 英雄养成 + Dota2 风格装备。目标平台：PC / Mac 独立版（Steam、itch.io）。

## 目录结构

```
td-hero-defense/
├─ project.godot
├─ data/                     JSON 配置表（数值热更新）
│  ├─ hero_def.json          12 名英雄：属性/成长/4 技能
│  ├─ item_def.json          17 件装备 + 8 条词条
│  └─ enemy_def.json         9 种小兵/Boss
├─ scripts/
│  ├─ core/                  ★ 纯逻辑层，零 Node 依赖，可 headless 测试
│  │  ├─ grid.gd             网格 / 流场 / 放置合法性（含堵路检测）
│  │  ├─ rng.gd              可复现随机数 + 加权抽样
│  │  ├─ balance.gd          所有数值公式集中处
│  │  ├─ battle.gd           实体创建 / 伤害结算 / 升级
│  │  ├─ experience.gd       经验归属（Tag & Carry）
│  │  ├─ support.gd          支援二选一（卡牌生成 + 去重）
│  │  ├─ wave_manager.gd     波次编队生成
│  │  └─ run_state.gd        全局状态机
│  ├─ game/                  引擎适配层（唯一依赖 Node 的目录）
│  │  ├─ main.gd             主控制器
│  │  ├─ battlefield.gd      战场渲染
│  │  └─ support_panel.gd    二选一 UI
│  └─ sim/                   无头数值模拟器
├─ tools/sim/sim_runner.gd    批量跑 1000 局调数值
├─ tests/test_runner.gd       核心逻辑单测（headless）
└─ scripts/
   ├─ test.bat               跑测试
   └─ build.bat              构建导出
```

## 常用命令

```bash
# 跑核心测试
godot --headless --path . --script res://tests/test_runner.gd

# 跑 1000 局数值模拟
godot --headless --path . --script res://tools/sim/sim_runner.gd -- 1000 1000

# 导出 Windows 版
godot --headless --path . --export-release "Windows Desktop" build/windows/TDHeroDefense.exe
```

Windows 下用 `scripts\test.bat` / `scripts\build.bat` 更省事。

## 架构原则

**core 层零引擎依赖。** 所有规则判定在 `scripts/core/`，不 import 任何 Node 类。
带来的收益：
- headless 单测，不需要开窗口（CI 可跑）
- 无头模拟器一天能跑 1000 局，改数值不用手玩
- 将来若换引擎（如 Cocos），只重写 `game/` 层

## 已实现的核心机制

| 机制 | 文件 | 说明 |
|---|---|---|
| 流场寻路 | `core/grid.gd` | 反向 BFS 预计算，敌人 O(1) 取方向 |
| 堵路检测 | `core/grid.gd` | 放置前临时占位 + BFS 可达性校验 + 死角检测 |
| 经验归属 | `core/experience.gd` | Tag & Carry + 最后一击保底 25% + 公共池兜底 |
| 支援二选一 | `core/support.gd` | 5 波一次，只排除**已选中**的英雄，加权抽样 |
| 装备系统 | `data/item_def.json` | 属性 + 主动/被动 + 词条 |
| 数值公式 | `core/balance.gd` | HP/金币/经验/减伤/派生属性全集中 |

## ⚠️ 版权提醒

本项目借鉴 Dota2 的**玩法机制与数值思路**，但角色、物品名称、美术资源**全部原创**。
Dota2 及其美术资源版权归 Valve 所有，不可用于商业发行。
