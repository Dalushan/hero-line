class_name TDTower
extends RefCounted
## 防御塔：建在进攻路线格上，负责持续输出。
## 纯逻辑层，无 Node 依赖。
##
## 设计要点：塔建在路线格 → 会改变敌人路径 → 必须配合 TDGrid.can_place() 做可达性校验。
## 塔本身不占格子阻挡（格子被标记为 BLOCKED，塔站在上面攻击）。

## 创建一座塔
static func create_tower(def: Dictionary, cell: Vector2i, id: int) -> Dictionary:
	return {
		"id": "t_%d" % id,
		"def_id": String(def.get("id", "")),
		"name": String(def.get("name", "")),
		"cell": cell,
		"dmg": float(def.get("dmg", 10.0)),
		"interval": float(def.get("interval", 1.0)),
		"range": float(def.get("range", 3.0)),
		"splash": float(def.get("splash", 0.0)),
		"slow": float(def.get("slow", 0.0)),
		"slow_time": float(def.get("slowTime", 0.0)),
		"chain": int(def.get("chain", 0)),
		"cost": int(def.get("cost", 100)),
		"level": 1,
		"next_atk": 0.0,
		"kills": 0,
		"total_damage": 0.0,
	}


## 塔最高等级
const MAX_LEVEL := 5

## 升级费用：基础价 × 等级系数
static func upgrade_cost(tower: Dictionary) -> int:
	var lvl: int = int(tower.get("level", 1))
	return int(round(float(tower.get("cost", 100)) * (0.7 + 0.5 * float(lvl))))


## 升级塔：提升伤害与射程
## 伤害倍率是玩家后期的主要成长来源，必须足够陡峭才能跟上敌人 HP 曲线
static func upgrade_tower(tower: Dictionary) -> bool:
	var lvl: int = int(tower.get("level", 1))
	if lvl >= MAX_LEVEL:
		return false
	var base_dmg: float = float(tower.get("dmg", 10.0))
	var base_range: float = float(tower.get("range", 3.0))
	tower["level"] = lvl + 1
	tower["dmg"] = base_dmg * (1.0 + 0.55 * float(lvl))
	tower["range"] = base_range * (1.0 + 0.10 * float(lvl))
	return true


## 找射程内最优先的目标
## 优先级：路径进度最靠前的（离基地最近）→ 优先击杀快到家的敌人
static func find_target(tower: Dictionary, enemies: Array, grid: TDGrid) -> Dictionary:
	var best := {}
	var best_progress := 1e18
	var rng: float = float(tower.get("range", 3.0))
	var tcell: Vector2i = tower.get("cell", Vector2i.ZERO)
	for e in enemies:
		if not bool(e.get("alive", false)):
			continue
		var ec: Vector2i = e.get("cell", Vector2i.ZERO)
		var d: float = float(abs(ec.x - tcell.x) + abs(ec.y - tcell.y))
		if d > rng:
			continue
		# 进度 = 到基地的流场距离，越小越接近基地
		var progress := 1e18
		if grid.flow_dist.size() == grid.width * grid.height:
			var fd: int = grid.flow_dist[grid.idx(ec.x, ec.y)]
			if fd != TDGrid.INF:
				progress = float(fd)
		# ★ 必须用 "best.is_empty() or progress < best_progress"：
		#   流场不可达的格子 progress 是极大值，用 "progress < best_progress"
		#   且初值为 -1.0 会导致永远选不中目标（塔完全不开火）
		if best.is_empty() or progress < best_progress:
			best_progress = progress
			best = e
	return best


## 塔攻击一次。返回造成的总伤害。
static func attack(tower: Dictionary, enemies: Array, grid: TDGrid, now: float) -> float:
	var target := find_target(tower, enemies, grid)
	if target.is_empty():
		tower["next_atk"] = now + float(tower.get("interval", 1.0))
		return 0.0

	var dmg: float = float(tower.get("dmg", 10.0))
	var total := 0.0

	# 连锁（雷塔）
	var chain_count: int = int(tower.get("chain", 0))
	if chain_count > 0:
		var hit := target
		var chained := 0
		while chained < chain_count and not hit.is_empty():
			total += _deal(hit, dmg, tower, grid, enemies)
			chained += 1
			hit = _find_next_chain(hit, enemies, grid, tower, dmg, chained)
	else:
		total += _deal(target, dmg, tower, grid, enemies)

	tower["next_atk"] = now + float(tower.get("interval", 1.0))
	tower["total_damage"] = float(tower.get("total_damage", 0.0)) + total
	return total


## 对单个敌人造成伤害（含溅射与减速）
static func _deal(enemy: Dictionary, dmg: float, tower: Dictionary, grid: TDGrid, enemies: Array) -> float:
	var applied := TDBattle.apply_damage_to_enemy(enemy, dmg)
	# 减速
	var slow: float = float(tower.get("slow", 0.0))
	if slow > 0.0:
		enemy["slow_factor"] = minf(float(enemy.get("slow_factor", 1.0)), 1.0 - slow)
		enemy["slow_until"] = maxf(float(enemy.get("slow_until", 0.0)), float(tower.get("_now", 0.0)) + float(tower.get("slow_time", 1.0)))
	# 溅射
	var splash: float = float(tower.get("splash", 0.0))
	if splash > 0.0:
		var ec: Vector2i = enemy.get("cell", Vector2i.ZERO)
		for other in enemies:
			if other == enemy or not bool(other.get("alive", false)):
				continue
			var oc: Vector2i = other.get("cell", Vector2i.ZERO)
			var d: float = float(abs(oc.x - ec.x) + abs(oc.y - ec.y))
			if d <= splash:
				applied += TDBattle.apply_damage_to_enemy(other, dmg * 0.5)
	return applied


## 连锁的下一个目标（最近的未被击中过的敌人）
static func _find_next_chain(source: Dictionary, enemies: Array, grid: TDGrid, tower: Dictionary, dmg: float, already: int) -> Dictionary:
	var best := {}
	var best_d := 9999.0
	var sc: Vector2i = source.get("cell", Vector2i.ZERO)
	var rng: float = float(tower.get("range", 3.0)) + 2.0
	for e in enemies:
		if not bool(e.get("alive", false)):
			continue
		if e == source:
			continue
		var ec: Vector2i = e.get("cell", Vector2i.ZERO)
		var d: float = float(abs(ec.x - sc.x) + abs(ec.y - sc.y))
		if d < best_d and d <= rng:
			best_d = d
			best = e
	return best
