class_name TDSupport
extends RefCounted
## 支援二选一系统 —— 每 5 波触发，卡牌 = 英雄 + 随机装备
## 约束：已被「选中」的英雄不再出现（未选中的不受限）

const RARITY_WEIGHT_BONUS_WAVE := 20   ## 第 20 波后稀有英雄权重加成
const RARITY_BONUS_MULT := 1.5


## 生成两张候选卡牌
## state: { "selected_hero_ids": Array[String], "wave": int }
static func roll_cards(heroes: Array, items: Array, state: Dictionary, rng: TDRng) -> Array:
	var selected: Array = state.get("selected_hero_ids", [])
	var wave: int = int(state.get("wave", 0))

	# 过滤掉已选过的英雄
	var pool: Array = []
	var weights: Array[float] = []
	for h in heroes:
		var hid: String = String(h.get("id", ""))
		if hid == "" or selected.has(hid):
			continue
		var w: float = float(h.get("rarityWeight", 10.0))
		if wave >= RARITY_WEIGHT_BONUS_WAVE and String(h.get("rarity", "")) in ["rare", "legendary"]:
			w *= RARITY_BONUS_MULT
		pool.append(h)
		weights.append(w)

	if pool.size() == 0:
		return []

	var picked: Array = rng.weighted_sample(pool, weights, 2)
	var cards: Array = []
	for hero in picked:
		cards.append({
			"hero_id": String(hero.get("id", "")),
			"hero_name": String(hero.get("name", "")),
			"hero_rarity": String(hero.get("rarity", "common")),
			"item": roll_item(hero, items, rng),
			"level": 1,
			"skill_levels": [0, 0, 0, 0],
		})
	return cards


## 按英雄类型加权抽取装备
static func roll_item(hero: Dictionary, items: Array, rng: TDRng) -> Dictionary:
	if items.is_empty():
		return {}
	var hero_type: String = String(hero.get("type", ""))
	var role: String = String(hero.get("role", ""))

	# 推导该英雄偏好的装备标签
	var wanted: Array[String] = []
	if hero_type.begins_with("melee_physical") or role in ["carry", "assassin"]:
		wanted = ["physical"]
	elif hero_type.begins_with("ranged_magic"):
		wanted = ["magic"]
	elif role == "tank":
		wanted = ["tank"]
	elif role == "support":
		wanted = ["support"]
	else:
		wanted = ["physical", "magic"]

	var pool: Array = []
	var weights: Array[float] = []
	for it in items:
		var tags: Array = it.get("tags", [])
		var w := 1.0
		for t in wanted:
			if tags.has(t):
				w *= 4.0
		pool.append(it)
		weights.append(w)

	var picked: Array = rng.weighted_sample(pool, weights, 1)
	if picked.is_empty():
		return {}
	return picked[0]


## 确认选择：把英雄加入已选池
static func commit_selection(cards: Array, chosen_index: int, state: Dictionary) -> void:
	if chosen_index < 0 or chosen_index >= cards.size():
		return
	var selected: Array = state.get("selected_hero_ids", [])
	var hero_id: String = String(cards[chosen_index].get("hero_id", ""))
	if hero_id != "" and not selected.has(hero_id):
		selected.append(hero_id)
	state["selected_hero_ids"] = selected
