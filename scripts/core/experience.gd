class_name TDExperience
extends RefCounted
## 经验归属 —— Tag & Carry 机制
##
## 规则：英雄攻击小兵时打标记，小兵死亡时「标记者」获得全部经验；
##       最后一击者保底拿 25%；标记者死亡/标记过期则由最后一击者兜底。
## 纯逻辑，无 Node 依赖，可 headless 单测。

const TAG_DURATION := 3.0      ## 标记保留秒数
const LAST_HIT_SHARE := 0.25   ## 最后一击保底比例


## 在敌人身上打标记
static func apply_attack(attacker_id: String, attacker_exp_weight: float, enemy: Dictionary, now: float) -> void:
	enemy["tag_hero_id"] = attacker_id
	enemy["tag_at"] = now
	enemy["tag_weight"] = attacker_exp_weight


## 结算一次击杀，返回 {hero_id: exp_amount} 映射
static func settle_kill(enemy: Dictionary, last_hit_id: String, hero_alive: Dictionary, now: float) -> Dictionary:
	var out := {}
	var total_exp: float = float(enemy.get("exp_value", 0))
	if total_exp <= 0.0:
		return out

	var tag_id: String = String(enemy.get("tag_hero_id", ""))
	var tag_at: float = float(enemy.get("tag_at", -999.0))
	var tag_valid := false
	if tag_id != "" and now - tag_at <= TAG_DURATION:
		if bool(hero_alive.get(tag_id, false)):
			tag_valid = true

	var last_hit_alive := last_hit_id != "" and bool(hero_alive.get(last_hit_id, false))

	if tag_valid:
		# 标记者拿全额
		out[tag_id] = out.get(tag_id, 0.0) + total_exp
		# 最后一击者保底（若不是标记者本人）
		if last_hit_alive and last_hit_id != tag_id:
			out[last_hit_id] = out.get(last_hit_id, 0.0) + total_exp * LAST_HIT_SHARE
	elif last_hit_alive:
		# 兜底：标记失效或标记者已死，最后一击者拿全额
		out[last_hit_id] = out.get(last_hit_id, 0.0) + total_exp
	else:
		# 极端情况：塔 AOE 秒杀且无有效标记者 → 经验进公共池
		out["__pool__"] = out.get("__pool__", 0.0) + total_exp
	return out
