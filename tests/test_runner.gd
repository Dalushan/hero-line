extends SceneTree
## Headless 测试运行器
## 用法: godot --headless --script res://tests/test_runner.gd
##
## 覆盖: 网格寻路 / 放置校验 / 经验归属 / 抽卡去重 / 数值曲线 / RNG 可复现

var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _init() -> void:
	print("=== TD Hero Defense · Core Test Suite ===")
	_run_all()
	print("")
	print("=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("\n--- Failures ---")
		for f in _failures:
			print("  ✗ " + f)
	quit(1 if _failed > 0 else 0)


func _run_all() -> void:
	test_grid_flow()
	test_grid_path_around_obstacle()
	test_place_blocking_path_rejected()
	test_place_on_ground_rejected()
	test_place_occupied_rejected()
	test_place_island_rejected()
	test_place_valid_accepted()
	test_next_step_moves_toward_base()
	test_experience_tag_and_carry()
	test_experience_tag_expired()
	test_experience_tagger_dead()
	test_experience_no_tag_last_hit()
	test_experience_aoe_no_tagger()
	test_experience_pool_fallback()
	test_support_no_repeat_selected()
	test_support_unselected_can_reappear()
	test_support_cards_distinct()
	test_support_weight_distribution()
	test_rng_reproducible()
	test_rng_weighted_sample_bounds()
	test_balance_hp_monotonic()
	test_balance_exp_monotonic()
	test_balance_level_up_threshold()
	test_balance_derived_stats()
	test_wave_manager_groups()
	test_wave_manager_boss_wave()
	test_wave_manager_unlock_schedule()
	test_enemy_creation()
	test_battle_damage_armor()
	test_battle_crit()
	test_battle_level_up()


# ---------------- helpers ----------------

func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)


func _eq(a, b, name: String) -> void:
	_ok(a == b, "%s (expected %s, got %s)" % [name, str(b), str(a)])


func _near(a: float, b: float, name: String, tol: float = 0.001) -> void:
	_ok(absf(a - b) <= tol, "%s (expected ~%s, got %s)" % [name, str(b), str(a)])


func _hero_def() -> Dictionary:
	return {
		"id": "hero_test", "name": "测试者", "type": "melee_physical", "role": "carry",
		"base": {"hp": 520, "str": 22, "agi": 24, "int": 12, "atk": 42,
				 "atkInterval": 0.9, "range": 2, "armor": 6, "magicResist": 20, "moveSpeed": 4.2},
		"growth": {"str": 1.8, "agi": 2.4, "int": 0.9},
		"skills": []
	}


# ---------------- grid tests ----------------

func test_grid_flow() -> void:
	var g := TDGrid.new()
	_ok(g.recompute_flow(), "flow: 出兵口应可达基地")
	_eq(g.flow_dist[g.idx(g.spawn_cell.x, g.spawn_cell.y)], 11, "flow: 距离应为 11")


func test_grid_path_around_obstacle() -> void:
	var g := TDGrid.new()
	# 在通路中段放一个障碍，路径应绕行
	g.set_cell(Vector2i(g.spawn_cell.x, g.spawn_cell.y + 3), TDGrid.Cell.BLOCKED)
	_ok(g.recompute_flow(), "flow: 绕行后仍可达")
	var step := g.next_step(Vector2i(g.spawn_cell.x, g.spawn_cell.y))
	_ok(step != Vector2i.ZERO, "next_step: 应给出绕行方向")


func test_place_blocking_path_rejected() -> void:
	var g := TDGrid.new()
	# 封死基地正前方
	var v := Vector2i(g.base_cell.x, g.base_cell.y - 1)
	g.set_cell(v, TDGrid.Cell.GROUND)
	g.recompute_flow()
	var r := g.can_place(v)
	_ok(not r["ok"], "放置: 封死路径应被拒绝")
	_ok(String(r["reason"]) != "", "放置: 拒绝时应给原因")


func test_place_on_ground_rejected() -> void:
	var g := TDGrid.new()
	var r := g.can_place(Vector2i(g.spawn_cell.x, g.spawn_cell.y + 1))
	_ok(not r["ok"], "放置: 通路格应被拒绝")
	_ok(String(r["reason"]).contains("通路"), "放置: 通路提示文案")


func test_place_occupied_rejected() -> void:
	var g := TDGrid.new()
	var v: Vector2i = g.buildable_cells()[0]
	g.set_cell(v, TDGrid.Cell.BLOCKED)
	var r := g.can_place(v)
	_ok(not r["ok"], "放置: 已占用格应被拒绝")


func test_place_island_rejected() -> void:
	var g := TDGrid.new()
	# 围出一个死角：把某个建造格四周全封住
	var target: Vector2i = g.buildable_cells()[0]
	g.set_cell(target, TDGrid.Cell.GROUND)
	# 手动构造：target 周围
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = target + dir
		if g.in_bounds(n.x, n.y):
			g.set_cell(n, TDGrid.Cell.BLOCKED)
	g.recompute_flow()
	var r := g.can_place(target)
	_ok(not r["ok"], "放置: 死角应被拒绝")


func test_place_valid_accepted() -> void:
	var g := TDGrid.new()
	var r := g.can_place(g.buildable_cells()[0])
	_ok(r["ok"], "放置: 普通建造格应允许")


func test_next_step_moves_toward_base() -> void:
	var g := TDGrid.new()
	g.recompute_flow()
	var step := g.next_step(g.spawn_cell)
	_ok(step != Vector2i.ZERO, "next_step: 应有方向")
	var cur := g.flow_dist[g.idx(g.spawn_cell.x, g.spawn_cell.y)]
	var nxt := g.flow_dist[g.idx(g.spawn_cell.x + step.x, g.spawn_cell.y + step.y)]
	_ok(nxt == cur - 1, "next_step: 应使流场距离减 1")


# ---------------- experience tests ----------------

func test_experience_tag_and_carry() -> void:
	var e := {"exp_value": 100, "tag_hero_id": "", "tag_at": -999.0}
	TDExperience.apply_attack("h1", 1.0, e, 100.0)
	var res := TDExperience.settle_kill(e, "h1", {"h1": true}, 100.5)
	_eq(res.get("h1", 0.0), 100.0, "经验: 标记者拿全额")


func test_experience_tag_expired() -> void:
	var e := {"exp_value": 100, "tag_hero_id": "", "tag_at": -999.0}
	TDExperience.apply_attack("h1", 1.0, e, 100.0)
	# 超过 3 秒标记过期
	var res := TDExperience.settle_kill(e, "h2", {"h1": true, "h2": true}, 110.0)
	_eq(res.get("h2", 0.0), 100.0, "经验: 标记过期后最后一击者兜底")
	_ok(not res.has("h1"), "经验: 过期标记不应发经验")


func test_experience_tagger_dead() -> void:
	var e := {"exp_value": 100, "tag_hero_id": "", "tag_at": -999.0}
	TDExperience.apply_attack("h1", 1.0, e, 100.0)
	var res := TDExperience.settle_kill(e, "h2", {"h1": false, "h2": true}, 100.5)
	_eq(res.get("h2", 0.0), 100.0, "经验: 标记者已死则最后一击者拿全额")
	_ok(not res.has("h1"), "经验: 死亡标记者不得经验")


func test_experience_no_tag_last_hit() -> void:
	var e := {"exp_value": 100, "tag_hero_id": "", "tag_at": -999.0}
	var res := TDExperience.settle_kill(e, "h3", {"h3": true}, 100.0)
	_eq(res.get("h3", 0.0), 100.0, "经验: 无标记时最后一击者全额")


func test_experience_aoe_no_tagger() -> void:
	# 塔 AOE 秒杀，无有效标记者 → 公共池
	var e := {"exp_value": 100, "tag_hero_id": "dead_hero", "tag_at": 100.0}
	var res := TDExperience.settle_kill(e, "", {}, 100.5)
	_eq(res.get("__pool__", 0.0), 100.0, "经验: 无归属进公共池")


func test_experience_pool_fallback() -> void:
	var e := {"exp_value": 50, "tag_hero_id": "", "tag_at": -999.0}
	var res := TDExperience.settle_kill(e, "", {}, 1.0)
	_eq(res.get("__pool__", 0.0), 50.0, "经验: 彻底无归属进公共池")


# ---------------- support tests ----------------

func _make_heroes(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"id": "hero_%d" % i, "name": "H%d" % i, "type": "melee_physical",
					"role": "carry", "rarity": "common", "rarityWeight": 60.0})
	return out


func test_support_no_repeat_selected() -> void:
	var heroes := _make_heroes(6)
	var items: Array = []
	var state := {"selected_hero_ids": ["hero_0", "hero_1"], "wave": 10}
	var rng := TDRng.new(12345)
	for _i in range(30):
		var cards := TDSupport.roll_cards(heroes, items, state, rng)
		for c in cards:
			_ok(not ["hero_0", "hero_1"].has(String(c["hero_id"])),
				"抽卡: 已选英雄 " + String(c["hero_id"]) + " 不应再出现")
		if cards.size() >= 2:
			TDSupport.commit_selection(cards, 0, state)


func test_support_unselected_can_reappear() -> void:
	var heroes := _make_heroes(4)
	var items: Array = []
	var state := {"selected_hero_ids": ["hero_0"], "wave": 5}
	var rng := TDRng.new(999)
	var seen := {}
	for _i in range(40):
		var cards := TDSupport.roll_cards(heroes, items, state, rng)
		for c in cards:
			seen[String(c["hero_id"])] = true
	_ok(seen.has("hero_1"), "抽卡: 未选过的英雄应能再次出现")


func test_support_cards_distinct() -> void:
	var heroes := _make_heroes(8)
	var items: Array = []
	var state := {"selected_hero_ids": [], "wave": 5}
	var rng := TDRng.new(777)
	for _i in range(50):
		var cards := TDSupport.roll_cards(heroes, items, state, rng)
		if cards.size() == 2:
			_ok(cards[0]["hero_id"] != cards[1]["hero_id"], "抽卡: 两张卡牌英雄必须不同")


func test_support_weight_distribution() -> void:
	# 稀有英雄在第 20 波后权重 ×1.5，应出现更多
	var heroes := [
		{"id": "common1", "name": "C1", "type": "melee_physical", "role": "carry", "rarity": "common", "rarityWeight": 60.0},
		{"id": "rare1", "name": "R1", "type": "melee_physical", "role": "carry", "rarity": "rare", "rarityWeight": 10.0},
	]
	var items: Array = []
	var state := {"selected_hero_ids": [], "wave": 25}
	var rng := TDRng.new(2024)
	var rare_count := 0
	var total := 0
	for _i in range(500):
		var cards := TDSupport.roll_cards(heroes, items, state, rng)
		for c in cards:
			total += 1
			if String(c["hero_id"]) == "rare1":
				rare_count += 1
	var ratio := float(rare_count) / maxf(float(total), 1.0)
	_ok(ratio > 0.15, "抽卡权重: 第25波稀有出现率应 >15% (实际 %.1f%%)" % (ratio * 100.0))


# ---------------- rng tests ----------------

func test_rng_reproducible() -> void:
	var a := TDRng.new(42)
	var b := TDRng.new(42)
	for _i in range(100):
		_eq(a.randi_range(0, 100000), b.randi_range(0, 100000), "RNG: 同种子序列一致")


func test_rng_weighted_sample_bounds() -> void:
	var r := TDRng.new(5)
	var items := [1, 2, 3, 4, 5]
	var picked := r.weighted_sample(items, [1.0, 1.0, 1.0, 1.0, 1.0], 3)
	_eq(picked.size(), 3, "RNG: 抽样数量正确")
	for p in picked:
		_ok(items.has(p), "RNG: 抽样元素在原集合内")
	_ok(picked[0] != picked[1] and picked[1] != picked[2], "RNG: 不放回抽样无重复")


# ---------------- balance tests ----------------

func test_balance_hp_monotonic() -> void:
	var prev := 0.0
	for w in range(1, 31):
		var hp := TDBalance.enemy_hp(w)
		_ok(hp > prev, "数值: 第%d波血量应递增" % w)
		prev = hp


func test_balance_exp_monotonic() -> void:
	var prev := 0
	for w in range(1, 31):
		var e := TDBalance.enemy_exp(w)
		_ok(e > prev, "数值: 第%d波经验应递增" % w)
		prev = e


func test_balance_level_up_threshold() -> void:
	var h := TDBattle.create_hero(_hero_def(), 1)
	h["exp"] = TDBalance.exp_to_level(2)
	var ups := TDBattle.check_level_up(h)
	_eq(ups, 1, "升级: 达到阈值应升 1 级")
	_eq(h["level"], 2, "升级: 等级正确")


func test_balance_derived_stats() -> void:
	var s := TDBalance.derive_hero_stats(_hero_def(), 1)
	_ok(float(s["max_hp"]) > 0.0, "派生: HP 为正")
	_ok(float(s["attack"]) > 0.0, "派生: 攻击为正")
	_ok(float(s["armor"]) > 0.0, "派生: 护甲为正")
	_ok(float(s["magic_resist"]) > 0.0, "派生: 魔抗为正")
	# 等级越高，HP 越高
	var s5 := TDBalance.derive_hero_stats(_hero_def(), 5)
	_ok(float(s5["max_hp"]) > float(s["max_hp"]), "派生: 5级 HP 高于 1级")


# ---------------- wave tests ----------------

func test_wave_manager_groups() -> void:
	var rng := TDRng.new(31)
	for w in range(1, 31):
		var groups := TDWaveManager.build_wave(w, rng)
		_ok(groups.size() > 0, "波次: 第%d波应有编队" % w)
		for g in groups:
			_ok(int(g["count"]) > 0, "波次: 第%d波编队数量应 >0" % w)


func test_wave_manager_boss_wave() -> void:
	var rng := TDRng.new(77)
	var groups := TDWaveManager.build_wave(30, rng)
	var has_boss := false
	for g in groups:
		if String(g["enemy_id"]) == "boss_warden":
			has_boss = true
	_ok(has_boss, "波次: 第30波应包含 Boss")


func test_wave_manager_unlock_schedule() -> void:
	var rng := TDRng.new(5)
	# 第1波只有步兵
	var g1 := TDWaveManager.build_wave(1, rng)
	_eq(g1.size(), 1, "波次: 第1波只有 1 组")
	_eq(String(g1[0]["enemy_id"]), "creep_melee", "波次: 第1波为步兵")
	# 第3波应含弓手
	var g3 := TDWaveManager.build_wave(3, rng)
	var has_ranged := false
	for g in g3:
		if String(g["enemy_id"]) == "creep_ranged":
			has_ranged = true
	_ok(has_ranged, "波次: 第3波应解锁弓手")


# ---------------- battle tests ----------------

func test_enemy_creation() -> void:
	var e := TDBattle.create_enemy({"id": "creep_melee", "name": "步兵", "tag": "physical",
		"hpMul": 1.0, "atkMul": 1.0, "armor": 2, "magicResist": 0, "moveSpeed": 1.6,
		"atkInterval": 1.2, "bountyMul": 1.0, "expMul": 1.0, "damageToBase": 10}, 1, 0)
	_ok(float(e["hp"]) > 0.0, "敌人: HP 为正")
	_eq(int(e["exp_value"]), TDBalance.enemy_exp(1), "敌人: 经验值匹配公式")
	_eq(int(e["bounty"]), TDBalance.enemy_gold(1), "敌人: 金币匹配公式")


func test_battle_damage_armor() -> void:
	# 护甲越高伤害越低
	var d0 := TDBalance.physical_damage(100.0, 0.0)
	var d50 := TDBalance.physical_damage(100.0, 50.0)
	var d100 := TDBalance.physical_damage(100.0, 100.0)
	_ok(d0 > d50, "伤害: 0护甲伤害高于50护甲")
	_ok(d50 > d100, "伤害: 50护甲伤害高于100护甲")
	_eq(d50, 50.0, "伤害: 50护甲减伤 50%")


func test_battle_crit() -> void:
	var normal := TDBalance.physical_damage(100.0, 0.0, false)
	var crit := TDBalance.physical_damage(100.0, 0.0, true)
	_eq(crit, normal * 2.0, "伤害: 暴击为 2 倍")


func test_battle_level_up() -> void:
	var h := TDBattle.create_hero(_hero_def(), 1)
	h["_def"] = _hero_def()
	h["exp"] = 999999
	var ups := TDBattle.check_level_up(h)
	_ok(ups > 0, "升级: 大量经验应连升多级")
	_eq(h["level"], 15, "升级: 等级上限 15")
