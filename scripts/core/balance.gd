class_name TDBalance
extends RefCounted
## 数值公式集中处。所有平衡调整只改这里 + data/*.json。


## ===== 数值平衡核心约束 =====
## 敌人 HP 指数增长 vs 玩家 DPS 近线性增长 —— 指数永远赢。
## 敌人血量增长率必须压到接近玩家成长速度，否则 20 波后必然无解。
##
## 推算：30 波需要 DPS = 数量×HP/可用交战时间
##   玩家 DPS ≈ 英雄(4×~100) + 塔(12×~45) ≈ 900
##   波30: 28只 × 60×g^29 / 交战时间 ≈ 900
##   → g ≈ 1.05~1.08（不是 1.11）
## 结论：取 g = 1.075，并在塔升级上补足成长空间。

## 小兵血量
static func enemy_hp(wave: int) -> float:
	var w: int = maxi(wave, 1)
	var growth: float = pow(1.075, float(w - 1))
	var base: float = 60.0 * growth
	var chapter: float = floor(float(w) / 10.0)
	return base * (1.0 + 0.02 * chapter * chapter)


## 小兵金币
static func enemy_gold(wave: int) -> int:
	var w: int = maxi(wave, 1)
	var growth: float = pow(1.06, float(w - 1))
	return int(round(8.0 * growth))


## 小兵经验
static func enemy_exp(wave: int) -> int:
	var w: int = maxi(wave, 1)
	var growth: float = pow(1.08, float(w - 1))
	return int(round(10.0 * growth))


## Boss 血量：独立调，不套小兵公式
static func boss_hp(wave: int) -> float:
	return enemy_hp(wave) * 90.0


## 敌人攻击力（独立曲线，不跟血量挂钩 —— 否则后期敌人一击秒英雄）
## 6 波时约 7 点伤害，30 波时约 20 点，英雄有足够时间打出输出
static func enemy_attack(wave: int) -> float:
	var w: int = maxi(wave, 1)
	var growth: float = pow(1.045, float(w - 1))
	return 6.0 * growth


## 波次通关奖励金币（保证即使英雄全灭也有收入，避免死亡螺旋）
static func wave_clear_gold(wave: int) -> int:
	var w: int = maxi(wave, 1)
	return int(round(25.0 + 6.0 * float(w)))


## 英雄复活费用
static func revive_cost(level: int) -> int:
	return 80 + 20 * maxi(level, 1)


## 波次间基地修复量（漏怪不至于直接崩盘，但也不能无限回血）
static func base_repair(wave: int) -> int:
	return 20 + 2 * maxi(wave, 1)


## ===== 金币回收机制 =====
## 实测后期金币会溢出到 1 万+（花不出去 = 数值设计失败）。
## 解决：让"商店"、"英雄技能升级"、"防御塔升级"共同吃金币，形成持续消耗。
## 商店每波刷新 3 件，价格递增（稀缺性保底），逼玩家做取舍。

## 技能升级费用（每级递增）
static func skill_upgrade_cost(skill_level: int) -> int:
	return 200 + 150 * maxi(skill_level, 0)


## 为英雄购买技能点（花金币）
## 返回 {ok: bool, reason: String}
static func buy_skill_point(hero: Dictionary, skill_index: int) -> Dictionary:
	var skills: Array = hero.get("skill_levels", [0, 0, 0, 0])
	if skill_index < 0 or skill_index >= skills.size():
		return {"ok": false, "reason": "无效技能"}
	var cur: int = int(skills[skill_index])
	if cur >= 3:
		return {"ok": false, "reason": "技能已满级"}
	var cost := skill_upgrade_cost(cur)
	if int(hero.get("gold", 0)) < cost:
		return {"ok": false, "reason": "金币不足"}
	skills[skill_index] = cur + 1
	hero["skill_levels"] = skills
	hero["gold"] = int(hero.get("gold", 0)) - cost
	return {"ok": true, "reason": ""}


## 商店物品池（消耗金币的出口）
const SHOP_ITEMS := [
	{"id": "buff_atk", "name": "攻击训练", "cost": 150, "kind": "buff", "value": "atk", "amount": 8.0},
	{"id": "buff_hp", "name": "体质训练", "cost": 150, "kind": "buff", "value": "hp", "amount": 150.0},
	{"id": "buff_armor", "name": "护甲训练", "cost": 180, "kind": "buff", "value": "armor", "amount": 4.0},
	{"id": "buff_aspd", "name": "身法训练", "cost": 200, "kind": "buff", "value": "atk_interval", "amount": -0.08},
	{"id": "buff_crit", "name": "破绽洞察", "cost": 320, "kind": "buff", "value": "crit", "amount": 0.08},
	{"id": "buff_gold", "name": "商人之运", "cost": 250, "kind": "buff", "value": "gold_bonus", "amount": 0.15},
	{"id": "buff_revive", "name": "复苏符文", "cost": 400, "kind": "buff", "value": "revive_discount", "amount": 0.3},
	{"id": "buff_tower", "name": "工事强化", "cost": 260, "kind": "buff", "value": "tower_dmg", "amount": 0.12},
]

## 商店第 N 波的价格倍率（波次越高越贵，制造稀缺感）
static func shop_price_mult(wave: int) -> float:
	return 1.0 + 0.02 * float(maxi(wave, 1))


## 应用一个商店 buff 到某个英雄（返回是否成功）
static func apply_shop_buff(hero: Dictionary, item: Dictionary) -> bool:
	if not bool(hero.get("alive", false)):
		return false
	var stats: Dictionary = hero.get("stats", {})
	var value: String = String(item.get("value", ""))
	var amount: float = float(item.get("amount", 0.0))
	match value:
		"atk":
			stats["attack"] = float(stats.get("attack", 0.0)) + amount
		"hp":
			stats["max_hp"] = float(stats.get("max_hp", 0.0)) + amount
			hero["hp"] = float(hero.get("hp", 0.0)) + amount
		"armor":
			stats["armor"] = float(stats.get("armor", 0.0)) + amount
		"atk_interval":
			stats["atk_interval"] = maxf(0.2, float(stats.get("atk_interval", 1.0)) + amount)
		"crit":
			stats["crit_chance"] = float(stats.get("crit_chance", 0.0)) + amount
		"gold_bonus":
			hero["gold_bonus"] = float(hero.get("gold_bonus", 0.0)) + amount
		"revive_discount":
			hero["revive_discount"] = float(hero.get("revive_discount", 0.0)) + amount
		"tower_dmg":
			hero["tower_dmg_bonus"] = float(hero.get("tower_dmg_bonus", 0.0)) + amount
		_:
			return false
	return true


## 升到第 N 级所需经验
## 前期必须快速升级：英雄等级是玩家主要的 DPS 成长来源
static func exp_to_level(level: int) -> int:
	var l: int = maxi(level, 1)
	var growth: float = pow(1.18, float(l - 1))
	return int(round(40.0 * growth))


## 升级后属性倍率
static func level_attr_multiplier(level: int) -> float:
	return pow(1.08, float(maxi(level - 1, 0)))


static func level_hp_multiplier(level: int) -> float:
	return 1.0 + 0.12 * float(maxi(level - 1, 0))


## 护甲减伤公式
static func armor_reduction(armor: float) -> float:
	return armor / (armor + 50.0)


static func magic_reduction(mr: float) -> float:
	return mr / (mr + 60.0)


## 物理伤害结算
static func physical_damage(raw: float, armor: float, is_crit: bool = false) -> float:
	var dmg: float = raw
	if is_crit:
		dmg *= 2.0
	return maxf(dmg * (1.0 - armor_reduction(armor)), 1.0)


## 魔法伤害结算
static func magic_damage(raw: float, magic_resist: float) -> float:
	return maxf(raw * (1.0 - magic_reduction(magic_resist)), 1.0)


## 英雄最终攻击力
static func hero_attack(base: float, main_stat: float, is_melee: bool) -> float:
	if is_melee:
		return base + main_stat * 0.9
	return base + main_stat * 0.7


## 派生最终属性
static func derive_hero_stats(h: Dictionary, level: int) -> Dictionary:
	var b: Dictionary = h.get("base", {})
	var g: Dictionary = h.get("growth", {})
	var mult: float = level_attr_multiplier(level)
	var hp_mult: float = level_hp_multiplier(level)

	var str_v: float = float(b.get("str", 0)) + float(g.get("str", 0)) * float(level - 1)
	var agi_v: float = float(b.get("agi", 0)) + float(g.get("agi", 0)) * float(level - 1)
	var int_v: float = float(b.get("int", 0)) + float(g.get("int", 0)) * float(level - 1)
	str_v *= mult
	agi_v *= mult
	int_v *= mult

	var is_melee: bool = String(h.get("type", "")).begins_with("melee")
	var main_stat: float = 0.0
	if is_melee:
		main_stat = maxf(str_v, agi_v)
	else:
		main_stat = int_v

	return {
		"str": str_v, "agi": agi_v, "int": int_v,
		"max_hp": (float(b.get("hp", 100)) + str_v * 22.0) * hp_mult,
		"hp_regen": float(b.get("hpRegen", 0)) + str_v * 0.3,
		"attack": hero_attack(float(b.get("atk", 0)), main_stat, is_melee),
		"atk_interval": float(b.get("atkInterval", 1.0)),
		"attack_range": float(b.get("range", 2)),
		"armor": float(b.get("armor", 0)) + agi_v * 0.7,
		"magic_resist": float(b.get("magicResist", 0)) + int_v * 0.5,
		"move_speed": float(b.get("moveSpeed", 3.0)) + agi_v * 0.02,
		"spell_power": int_v * 0.9,
	}


## 波次间隔（秒）
static func wave_interval() -> float:
	return 8.0


## 每 5 波触发一次支援二选一
static func is_support_wave(wave: int) -> bool:
	return wave % 5 == 0


## 一关总波数
static func waves_per_stage() -> int:
	return 30
