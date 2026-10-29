# TD Hero Defense · Godot 4.7

塔防 + 英雄养成 + Dota2 风格装备。目标平台：PC / Mac 独立版（Steam、itch.io）。

**当前状态**：核心玩法闭环已跑通，单测 467 项全绿，模拟器 30 波通关率 73.3%，可导出 Windows 可执行文件。

## 目录结构

```
td-hero-defense/
├─ project.godot
├─ data/                     JSON 配置表（数值热更新）
│  ├─ hero_def.json          12 名英雄：属性/成长/4 技能
│  ├─ item_def.json          17 件装备 + 8 条词条
│  ├─ enemy_def.json         9 种小兵/Boss
│  └─ tower_def.json         4 种防御塔
├─ scripts/
│  ├─ core/                  ★ 纯逻辑层，零 Node 依赖，可 headless 测试
│  │  ├─ grid.gd             网格 / 流场 / 放置合法性（含堵路检测）
│  │  ├─ rng.gd              可复现随机数 + 加权抽样
│  │  ├─ balance.gd          所有数值公式集中处（含商店 buff / 技能点）
│  │  ├─ battle.gd           实体创建 / 伤害结算 / 升级 / 波间治疗
│  │  ├─ engagement.gd       交战规则（近战停步 / 远程边走边打）
│  │  ├─ experience.gd       经验归属（Tag & Carry）
│  │  ├─ support.gd          支援二选一（卡牌生成 + 去重）
│  │  ├─ tower.gd            防御塔（4 种 + 5 级升级 + 溅射/减速/连锁）
│  │  ├─ wave_manager.gd     波次编队生成
│  │  └─ run_state.gd        全局状态机
│  ├─ game/                  引擎适配层（唯一依赖 Node 的目录）
│  │  ├─ main.gd             主控制器 / 玩家操作接线
│  │  ├─ battlefield.gd      战场渲染 + 鼠标交互 + HUD
│  │  ├─ build_bar.gd        建造栏（建塔 / 升级 / 取消）
│  │  ├─ support_panel.gd    支援二选一 UI
│  │  └─ shop_panel.gd       局内商店 UI
├─ tools/
│  ├─ sim/sim_runner.gd      批量跑局调数值
│  └─ screenshot.gd          自动截图（视觉验证）
├─ tests/test_runner.gd      核心逻辑单测（headless）
├─ docs/设计方案v0.1.md       完整设计方案（含实测教训）
└─ scripts/
   ├─ build.bat              构建导出（dev | export | test | sim）
   └─ test.bat               跑测试
```

## 常用命令

```bash
# 跑核心测试（467 项）
godot --headless --path . --script res://tests/test_runner.gd

# 跑数值模拟：局数 基准种子 [详细模式]
godot --headless --path . --script res://tools/sim/sim_runner.gd -- 30 7000
godot --headless --path . --script res://tools/sim/sim_runner.gd -- 1 1000 1   # 逐波明细

# 自动截图（验证渲染）
godot --path . --script res://tools/screenshot.gd

# 导出 Windows 版
godot --headless --path . --export-release "Windows Desktop" build/windows/TDHeroDefense.exe
```

Windows 下用 `scripts\build.bat dev|export|test|sim` 更省事。

### ⚠️ 导出模板安装位置

Godot 只认这个路径，**不是 Godot 安装目录**：

```
%APPDATA%\Godot\export_templates\4.7.2.stable\
```

（`%LOCALAPPDATA%\Programs\Godot\templates\` 放模板没用，导出时会报
「在预期路径处未找到导出模板」）

## 架构原则

**core 层零引擎依赖。** 所有规则判定在 `scripts/core/`，不 import 任何 Node 类。
实体用 `Dictionary` 表示，不继承 `Node`。
带来的收益：
- headless 单测，不需要开窗口（CI 可跑）
- 无头模拟器一天能跑 1000 局，改数值不用手玩
- 将来若换引擎（如 Cocos），只重写 `game/` 层

## 已实现的核心机制

| 机制 | 文件 | 说明 |
|---|---|---|
| 流场寻路 | `core/grid.gd` | 反向 BFS 预计算，敌人 O(1) 取方向；占位后必须重算 |
| 堵路检测 | `core/grid.gd` | 放置前临时占位 + BFS 可达性校验 + 死角检测 |
| 交战规则 | `core/engagement.gd` | 近战停步交战 / 远程边走边打（防卡死关键） |
| 防御塔 | `core/tower.gd` | 4 种塔 + 5 级升级 + 溅射/减速/连锁 |
| 经验归属 | `core/experience.gd` | Tag & Carry + 最后一击保底 25% + 公共池兜底 |
| 支援二选一 | `core/support.gd` | 5 波一次，只排除**已选中**的英雄，加权抽样 |
| 局内商店 | `core/balance.gd` | 8 种 buff，每波刷 3 件，价格随波次递增 |
| 技能点 | `core/balance.gd` | Dota2 风格购买（200/350/500 金） |
| 英雄成长 | `core/battle.gd` | 等级/经验/复活/波间治疗 |
| 数值公式 | `core/balance.gd` | HP/金币/经验/减伤/派生属性全集中 |

## 数值平衡现状（模拟器实测）

```
30 局 / seed 7000：通关率 73.3%，平均到达波次 29.6/30
最终金币 4400（不再溢出），平均剩余基地 HP 605/1000
```

关键约束（详见 `docs/设计方案v0.1.md` 的「实测教训」）：
- 敌人 HP 增长率 **1.075**（不是 1.11 —— 指数永远赢，玩家 DPS 只能近线性成长）
- 敌人攻击力走**独立曲线** `6×1.045^(w-1)`，不跟血量挂钩
- 金币必须有出口：商店 + 技能点 + 塔升级，否则后期溢出到 1 万+

## ⚠️ 版权提醒

本项目借鉴 Dota2 的**玩法机制与数值思路**，但角色、物品名称、美术资源**全部原创**。
Dota2 及其美术资源版权归 Valve 所有，不可用于商业发行。
代码中的 `dotaRef` 仅供内部机制映射，不对外暴露。
