class_name TDBalance
extends RefCounted
## 数值公式集中处。所有平衡调整只改这里 + data/*.json。


## 小兵血量
static func enemy_hp(wave: int) -> float:
	var w: int = max(wave, 1)
	var base := 60.0 * pow(1.11, w - 1)
	var chapter := floor(w / 10.0)
	return base * (1.0 + 0.02 * chapter * chapter)


## 小兵金币
static func enemy_gold(wave: int) -> int:
	var w: int = max(wave, 1)
	return int(round(8.0 * pow(1.06, w - 1)))


## 小兵经验
static func enemy_exp(wave: int) -> int:
	var w: int = max(wave, 1)
	return int(round(10.0 * pow(1.08, w - 1)))


## Boss 血量：独立调，不套小兵公式
static func boss_hp(wave: int) -> float:
	return enemy_hp(wave) * 90.0


## 到达第 N 波所需经验（用于英雄升级曲线）
static func exp_to_level(level: int) -> int:
	var l: int = max(level, 1)
	return int(round(60.0 * pow(1.25, l - 1)))


## 升级后属性倍率
static func level_attr_multiplier(level: int) -> float:
	return pow(1.08, max(level - 1, 0))


static func level_hp_multiplier(level: int) -> float:
	return 1.0 + 0.12 * max(level - 1, 0)


## 护甲减伤公式
static func armor_reduction(armor: float) -> float:
	return armor / (armor + 50.0)


static func magic_reduction(mr: float) -> float:
	return mr / (mr + 60.0)


## 物理伤害结算
static func physical_damage(raw: float, armor: float, is_crit: bool = false) -> float:
	var dmg := raw
	if is_crit:
		dmg *= 2.0
	return maxf(dmg * (1.0 - armor_reduction(armor)), 1.0)


## 魔法伤害结算
static func magic_damage(raw: float, magic_resist: float) -> float:
	return maxf(raw * (1.0 - magic_reduction(magic_resist)), 1.0)


## 英雄最终攻击力
static func hero_attack(base: float, main_stat: float, is_melee: bool) -> float:
	return base + main_stat * (0.9 if is_melee else 0.7)


## 派生最终属性
static func derive_hero_stats(h: Dictionary, level: int) -> Dictionary:
	var b: Dictionary = h.get("base", {})
	var g: Dictionary = h.get("growth", {})
	var mult := level_attr_multiplier(level)
	var hp_mult := level_hp_multiplier(level)

	var str := float(b.get("str", 0)) + float(g.get("str", 0)) * (level - 1)
	var agi := float(b.get("agi", 0)) + float(g.get("agi", 0)) * (level - 1)
	var inte := float(b.get("int", 0)) + float(g.get("int", 0)) * (level - 1)
	str *= mult
	agi *= mult
	inte *= mult

	var is_melee: bool = String(h.get("type", "")).begins_with("melee")
	var main_stat: float = maxi(str, agi) if is_melee else inte

	return {
		"str": str, "agi": agi, "int": inte,
		"max_hp": (float(b.get("hp", 100)) + str * 22.0) * hp_mult,
		"hp_regen": float(b.get("hpRegen", 0)) + str * 0.3,
		"attack": hero_attack(float(b.get("atk", 0)), main_stat, is_melee),
		"atk_interval": float(b.get("atkInterval", 1.0)),
		"attack_range": float(b.get("range", 2)),
		"armor": float(b.get("armor", 0)) + agi * 0.7,
		"magic_resist": float(b.get("magicResist", 0)) + inte * 0.5,
		"move_speed": float(b.get("moveSpeed", 3.0)) + agi * 0.02,
		"spell_power": inte * 0.9,
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
