class_name TDBattle
extends RefCounted
## 战斗核心：实体、伤害结算、攻击逻辑
## 纯逻辑层，所有实体用 Dictionary 表示，便于序列化与无头模拟。

const DAMAGE_TYPE_PHYSICAL := "physical"
const DAMAGE_TYPE_MAGIC := "magic"
const DAMAGE_TYPE_TRUE := "true"


## 创建一名英雄实体
static func create_hero(hero_def: Dictionary, level: int = 1) -> Dictionary:
	var stats := TDBalance.derive_hero_stats(hero_def, level)
	var hero := {
		"id": "h_%d" % Time.get_ticks_usec(),
		"def_id": String(hero_def.get("id", "")),
		"name": String(hero_def.get("name", "")),
		"type": String(hero_def.get("type", "")),
		"role": String(hero_def.get("role", "")),
		"level": level,
		"exp": 0,
		"cell": Vector2i.ZERO,
		"hp": float(stats["max_hp"]),
		"alive": true,
		"stats": stats,
		"skill_levels": [0, 0, 0, 0],
		"items": [],
		"buffs": [],
		"gold": 0,
		"kills": 0,
		"last_attack_at": -999.0,
		"attack_count": 0,
	}
	return hero


## 创建一名敌人实体
static func create_enemy(enemy_def: Dictionary, wave: int, id_seed: int) -> Dictionary:
	var hp_mul: float = float(enemy_def.get("hpMul", 1.0))
	var hp: float = TDBalance.enemy_hp(wave) * hp_mul
	var is_boss := String(enemy_def.get("tag", "")) == "boss"
	if is_boss:
		hp = TDBalance.boss_hp(wave)

	var armor: float = float(enemy_def.get("armor", 0))
	var mr: float = float(enemy_def.get("magicResist", 0))

	return {
		"id": "e_%d_%d" % [wave, id_seed],
		"def_id": String(enemy_def.get("id", "")),
		"name": String(enemy_def.get("name", "")),
		"tag": String(enemy_def.get("tag", "")),
		"wave": wave,
		"hp": hp,
		"max_hp": hp,
		"armor": armor,
		"magic_resist": mr,
		"attack": TDBalance.enemy_attack(wave) * float(enemy_def.get("atkMul", 1.0)),
		"atk_interval": float(enemy_def.get("atkInterval", 1.5)),
		"attack_range": float(enemy_def.get("attackRange", 1)),
		"move_speed": float(enemy_def.get("moveSpeed", 1.6)),
		"damage_to_base": int(enemy_def.get("damageToBase", 10)),
		"bounty": int(round(TDBalance.enemy_gold(wave) * float(enemy_def.get("bountyMul", 1.0)))),
		"exp_value": int(round(TDBalance.enemy_exp(wave) * float(enemy_def.get("expMul", 1.0)))),
		"cell": Vector2i.ZERO,
		"alive": true,
		"last_hit_by": "",
		"tag_hero_id": "",
		"tag_at": -999.0,
		"tag_weight": 1.0,
		"shield": hp * float(enemy_def.get("shieldRatio", 0.0)),
		"is_boss": is_boss,
	}


## 英雄攻击敌人：返回实际造成的伤害
static func hero_attack_enemy(hero: Dictionary, enemy: Dictionary, now: float) -> float:
	if not hero.get("alive", false) or not enemy.get("alive", false):
		return 0.0

	var stats: Dictionary = hero.get("stats", {})
	var raw: float = float(stats.get("attack", 10.0))

	# 暴击判定（以斩光者为例）
	var crit_chance := 0.0
	var crit_mult := 2.0
	if String(hero.get("def_id", "")) == "hero_zhan_guang":
		var sl: int = int(hero.get("skill_levels", [0, 0, 0, 0])[0])
		crit_chance = [0.0, 0.25, 0.30, 0.35][clampi(sl, 0, 3)]
		crit_mult = [0.0, 2.0, 2.4, 2.8][clampi(sl, 0, 3)]

	var is_crit := crit_chance > 0.0 and randf() < crit_chance
	var dmg := TDBalance.physical_damage(raw, float(enemy.get("armor", 0)), is_crit)

	# 打标记（Tag & Carry）
	TDExperience.apply_attack(
		String(hero.get("id", "")),
		1.0,
		enemy,
		now
	)
	enemy["last_hit_by"] = String(hero.get("id", ""))
	hero["attack_count"] = int(hero.get("attack_count", 0)) + 1

	return apply_damage_to_enemy(enemy, dmg)


## 对敌人造成伤害，返回实际扣血量
static func apply_damage_to_enemy(enemy: Dictionary, dmg: float) -> float:
	if not enemy.get("alive", false):
		return 0.0
	# 优先扣盾
	var shield: float = float(enemy.get("shield", 0.0))
	if shield > 0.0:
		var absorbed: float = minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
		enemy["shield"] = shield
	if dmg > 0.0:
		enemy["hp"] = float(enemy.get("hp", 0.0)) - dmg
		if enemy["hp"] <= 0.0:
			enemy["hp"] = 0.0
			enemy["alive"] = false
	return dmg


## 敌人攻击英雄
static func enemy_attack_hero(enemy: Dictionary, hero: Dictionary) -> float:
	if not enemy.get("alive", false) or not hero.get("alive", false):
		return 0.0
	var stats: Dictionary = hero.get("stats", {})
	var raw: float = float(enemy.get("attack", 5.0))
	var dmg := TDBalance.physical_damage(raw, float(stats.get("armor", 0)))
	hero["hp"] = float(hero.get("hp", 0.0)) - dmg
	if hero["hp"] <= 0.0:
		hero["hp"] = 0.0
		hero["alive"] = false
	return dmg


## 施加魔法伤害到英雄
static func magic_damage_to_hero(caster_stats: Dictionary, hero: Dictionary, raw: float) -> float:
	var stats: Dictionary = hero.get("stats", {})
	var dmg := TDBalance.magic_damage(raw, float(stats.get("magic_resist", 0)))
	hero["hp"] = float(hero.get("hp", 0.0)) - dmg
	if hero["hp"] <= 0.0:
		hero["hp"] = 0.0
		hero["alive"] = false
	return dmg


## 波次之间治疗：存活英雄在布防期回满血
## 这是塔防的标准约定（Kingdom Rush 等），否则累计伤害会让英雄在数波后必然阵亡
static func heal_between_waves(hero: Dictionary) -> void:
	if not bool(hero.get("alive", false)):
		return
	var max_hp: float = float(hero.get("stats", {}).get("max_hp", 100.0))
	hero["hp"] = max_hp


## 英雄升级检查，返回升级次数
static func check_level_up(hero: Dictionary) -> int:
	var level: int = int(hero.get("level", 1))
	var exp: int = int(hero.get("exp", 0))
	var ups := 0
	while level < 15:
		var need := TDBalance.exp_to_level(level + 1)
		if exp < need:
			break
		exp -= need
		level += 1
		ups += 1
		# 升级点：1/4/7/10/13 级各 +1 技能点
		if level in [4, 7, 10, 13]:
			hero["skill_points"] = int(hero.get("skill_points", 0)) + 1
	hero["level"] = level
	hero["exp"] = exp
	if ups > 0:
		# 重算属性并保持 HP 比例
		var def: Dictionary = hero.get("_def", {})
		if not def.is_empty():
			var old_max: float = float(hero.get("stats", {}).get("max_hp", 1.0))
			var ratio: float = float(hero.get("hp", 0.0)) / maxf(old_max, 0.001)
			var new_stats := TDBalance.derive_hero_stats(def, level)
			hero["stats"] = new_stats
			hero["hp"] = new_stats["max_hp"] * ratio
	return ups
