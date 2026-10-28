class_name TDEngagement
extends RefCounted
## 敌人推进与交战规则 —— core 层唯一实现。
## sim_runner 与 game/main.gd 共用这一份，避免规则漂移。
##
## ===== 关键规则：近战停步交战，远程边走边打 =====
## 早期版本让所有敌人在射程内都停下攻击，结果：
##   弓手(射程4) 站在距离英雄4格处停下开火，英雄(近战射程2) 打不到它
##   → 敌人不掉血也不前进 → 波次永久卡死（实测第3~6波必现）
## 正确做法（也是 Dota/LoL 惯例）：
##   近战敌人：遇到挡路的英雄 → 停下交战
##   远程敌人：继续前进，同时射击射程内的英雄（不因攻击而停步）

const STATUS_NONE := "none"
const STATUS_REACHED_BASE := "reached_base"
const STATUS_ENGAGED := "engaged"


## 找出射程内最近的存活英雄
static func nearest_hero_in_range(enemy: Dictionary, heroes: Array) -> Dictionary:
	var best := {}
	var best_d := 1e9
	var rng: float = float(enemy.get("attack_range", 1.0))
	var ec: Vector2i = enemy.get("cell", Vector2i.ZERO)
	for h in heroes:
		if not bool(h.get("alive", false)):
			continue
		var hc: Vector2i = h.get("cell", Vector2i.ZERO)
		var d: float = float(abs(ec.x - hc.x) + abs(ec.y - hc.y))
		if d <= rng and d < best_d:
			best_d = d
			best = h
	return best


## 敌人是否属于远程（射程 > 1）
static func is_ranged(enemy: Dictionary) -> bool:
	return float(enemy.get("attack_range", 1.0)) > 1.0


## 更新一个敌人：交战 + 移动。
## 返回 STATUS_* 之一。
static func update_enemy(enemy: Dictionary, state: TDRunState, now: float, dt: float) -> String:
	if not bool(enemy.get("alive", false)):
		return STATUS_NONE

	var atk_cd: float = float(enemy.get("atk_interval", 1.5))
	var target := nearest_hero_in_range(enemy, state.heroes)
	var ranged := is_ranged(enemy)

	# --- 交战 ---
	if not target.is_empty():
		if now >= float(enemy.get("_next_atk", 0.0)):
			TDBattle.enemy_attack_hero(enemy, target)
			enemy["_next_atk"] = now + atk_cd
		# 近战敌人停下交战；远程敌人继续前进
		if not ranged:
			return STATUS_ENGAGED

	# --- 移动 ---
	var speed: float = float(enemy.get("move_speed", 1.6))
	# 减速效果（霜塔）
	var slow_factor: float = float(enemy.get("slow_factor", 1.0))
	if now > float(enemy.get("slow_until", 0.0)):
		slow_factor = 1.0
		enemy["slow_factor"] = 1.0
	speed *= slow_factor

	var accum: float = float(enemy.get("_move_accum", 0.0)) + speed * dt
	var guard := 0
	while accum >= 1.0 and guard < 8:
		guard += 1
		var step := state.grid.next_step(enemy["cell"])
		if step == Vector2i.ZERO:
			# 无路可走 → 到达基地
			state.damage_base(int(enemy.get("damage_to_base", 10)))
			enemy["alive"] = false
			enemy["_reached_base"] = true
			enemy["_move_accum"] = 0.0
			return STATUS_REACHED_BASE
		enemy["cell"] = enemy["cell"] + step
		accum -= 1.0
	enemy["_move_accum"] = accum
	return STATUS_NONE


## 英雄攻击：找出射程内最近的存活敌人并攻击
static func hero_attack(hero: Dictionary, state: TDRunState, now: float) -> bool:
	if not bool(hero.get("alive", false)):
		return false
	var atk_cd: float = float(hero.get("stats", {}).get("atk_interval", 1.0))
	if now < float(hero.get("_next_atk", 0.0)):
		return false

	var rng: float = float(hero.get("stats", {}).get("attack_range", 2))
	var hc: Vector2i = hero.get("cell", Vector2i.ZERO)
	var best := {}
	var best_d := 1e9
	for e in state.enemies:
		if not bool(e.get("alive", false)):
			continue
		var ec: Vector2i = e.get("cell", Vector2i.ZERO)
		var d: float = float(abs(ec.x - hc.x) + abs(ec.y - hc.y))
		if d <= rng and d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		hero["_next_atk"] = now + 0.1
		return false

	TDBattle.hero_attack_enemy(hero, best, now)
	hero["_next_atk"] = now + atk_cd
	return true
