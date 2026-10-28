class_name TDRng
extends RefCounted
## 可复现随机数。同一 seed 必产生同一序列 —— 无头模拟与 bug 复现的基础。

var _rng := RandomNumberGenerator.new()
var seed_value: int


func _init(s: int = 0) -> void:
	seed_value = s
	_rng.seed = s


## 静态种子（由时间生成），用于真实对局
static func make_random_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi() & 0x7FFFFFFF


func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


func randf() -> float:
	return _rng.randf()


func chance(p: float) -> bool:
	return _rng.randf() < p


## 按权重不放回抽样 k 个。weights 与 items 等长。
func weighted_sample(items: Array, weights: Array[float], k: int) -> Array:
	var pool_items: Array = items.duplicate()
	var pool_weights: Array[float] = weights.duplicate()
	var picked: Array = []
	var n: int = min(k, pool_items.size())
	for _i in range(n):
		var total := 0.0
		for w in pool_weights:
			total += maxf(w, 0.0)
		if total <= 0.0:
			break
		var roll := _rng.randf() * total
		var acc := 0.0
		var chosen := -1
		for j in range(pool_items.size()):
			acc += maxf(pool_weights[j], 0.0)
			if roll <= acc:
				chosen = j
				break
		if chosen < 0:
			chosen = pool_items.size() - 1
		picked.append(pool_items[chosen])
		pool_items.remove_at(chosen)
		pool_weights.remove_at(chosen)
	return picked
