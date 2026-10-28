class_name TDWaveManager
extends RefCounted
## 波次调度：根据波次号生成编队（兵种/数量/间隔），并驱动出怪。
## 纯逻辑层。

## 兵种解锁节奏：wave -> array of enemy ids
const UNLOCK_SCHEDULE := {
	1: ["creep_melee"],
	3: ["creep_ranged"],
	6: ["creep_mage"],
	9: ["creep_armored"],
	12: ["creep_shield"],
	15: ["creep_swift"],
	18: ["creep_splitter"],
	21: ["elite_sentinel"],
	26: ["boss_warden"],
}

## 兵种在各波次的权重（越后期越多样）
const TYPE_WEIGHT := {
	"creep_melee": 100.0,
	"creep_ranged": 70.0,
	"creep_mage": 50.0,
	"creep_armored": 45.0,
	"creep_shield": 40.0,
	"creep_swift": 35.0,
	"creep_splitter": 30.0,
}


## 生成一波的编队
static func build_wave(wave: int, rng: TDRng) -> Array:
	var groups: Array = []
	var available: Array = []
	for w in range(1, wave + 1):
		for eid in UNLOCK_SCHEDULE.get(w, []):
			available.append(eid)

	if available.is_empty():
		available = ["creep_melee"]

	# Boss 波：单 Boss + 少量护卫
	if wave % 10 == 0 and wave >= 26:
		groups.append({"enemy_id": "boss_warden", "count": 1, "interval": 0.0, "delay": 0.0})
		var guard_pool: Array = available.duplicate()
		guard_pool.erase("boss_warden")
		if not guard_pool.is_empty():
			groups.append({
				"enemy_id": guard_pool[0],
				"count": mini(6 + wave / 3, 20),
				"interval": 0.8,
				"delay": 3.0
			})
		return groups

	# 精英波：每 10 波（20/30）
	if wave % 10 == 0:
		groups.append({"enemy_id": "elite_sentinel", "count": 1 + wave / 10, "interval": 2.0, "delay": 0.0})
		groups.append({
			"enemy_id": available[0],
			"count": mini(4 + wave / 4, 16),
			"interval": 0.7,
			"delay": 1.5
		})
		return groups

	# 普通波：1~3 个兵种组
	var group_count: int = 1
	if wave >= 6:
		group_count = 2
	if wave >= 14:
		group_count = 3

	var pool: Array = available.duplicate()
	var weights: Array[float] = []
	for eid in pool:
		weights.append(TYPE_WEIGHT.get(eid, 30.0))

	var chosen: Array = rng.weighted_sample(pool, weights, mini(group_count, pool.size()))
	for i in range(chosen.size()):
		var eid: String = String(chosen[i])
		var is_new: bool = false
		if available.size() > 1 and eid == String(available[available.size() - 1]):
			is_new = true
		var base_count: int = int(round(4.0 + wave * 0.8))
		var count: int = maxi(3, base_count + rng.randi_range(-1, 2))
		if is_new:
			count = maxi(2, int(count * 0.5))   # 新兵种首次出场少量登场，让玩家适应
		groups.append({
			"enemy_id": eid,
			"count": count,
			"interval": maxf(0.35, 1.1 - wave * 0.015),
			"delay": float(i) * 3.0
		})
	return groups


## 波次是否包含支援二选一
static func has_support(wave: int) -> bool:
	return wave % 5 == 0
