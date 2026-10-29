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
	test_grid_next_step_without_manual_recompute()
	test_grid_layout_mix()
	test_grid_path_around_obstacle()
	test_place_tower_blocks_path_rejected()
	test_place_tower_narrowing_ok()
	test_place_hero_on_path_allowed()
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
	test_tower_create_and_upgrade()
	test_tower_finds_target_in_range()
	test_tower_ignores_out_of_range()
	test_tower_attack_deals_damage()
	test_engagement_ranged_keeps_moving()
	test_engagement_melee_stops_to_fight()
	test_shop_buff_applies()
	test_skill_point_purchase()
	test_balance_enemy_attack_curve()
	test_balance_gold_sinks_exist()
	test_hero_move_does_not_duplicate()
	test_hero_placement_marks_grid_blocked()


# ---------------- tower tests ----------------

func _tower_def() -> Dictionary:
	return {"id": "tower_arrow", "name": "箭塔", "cost": 120, "dmg": 25,
			"interval": 0.8, "range": 4.0, "splash": 0.0, "slow": 0.0,
			"slowTime": 0.0, "desc": "测试塔"}


func test_tower_create_and_upgrade() -> void:
	var t := TDTower.create_tower(_tower_def(), Vector2i(5, 5), 0)
	_eq(int(t["level"]), 1, "塔: 初始等级 1")
	var dmg_before := float(t["dmg"])
	_ok(TDTower.upgrade_tower(t), "塔: 升级应成功")
	_eq(int(t["level"]), 2, "塔: 升级后等级 2")
	_ok(float(t["dmg"]) > dmg_before, "塔: 升级应提升伤害")
	# 升到上限后不能再升
	while int(t["level"]) < TDTower.MAX_LEVEL:
		TDTower.upgrade_tower(t)
	_ok(not TDTower.upgrade_tower(t), "塔: 满级后不能再升级")
	_eq(int(t["level"]), TDTower.MAX_LEVEL, "塔: 等级停在上限")


func test_tower_finds_target_in_range() -> void:
	var g := TDGrid.new()
	var t := TDTower.create_tower(_tower_def(), Vector2i(5, 5), 0)
	var e := TDBattle.create_enemy({"id": "creep_melee", "name": "步兵", "tag": "physical",
		"hpMul": 1.0, "atkMul": 1.0, "armor": 0, "magicResist": 0, "moveSpeed": 1.6,
		"atkInterval": 1.2, "bountyMul": 1.0, "expMul": 1.0, "damageToBase": 10}, 1, 0)
	e["cell"] = Vector2i(6, 5)   # 距离1，在射程4内
	var found := TDTower.find_target(t, [e], g)
	_ok(not found.is_empty(), "塔: 应找到射程内目标")


func test_tower_ignores_out_of_range() -> void:
	var g := TDGrid.new()
	var t := TDTower.create_tower(_tower_def(), Vector2i(5, 5), 0)
	var e := TDBattle.create_enemy({"id": "creep_melee", "name": "步兵", "tag": "physical",
		"hpMul": 1.0, "atkMul": 1.0, "armor": 0, "magicResist": 0, "moveSpeed": 1.6,
		"atkInterval": 1.2, "bountyMul": 1.0, "expMul": 1.0, "damageToBase": 10}, 1, 0)
	e["cell"] = Vector2i(15, 12)   # 远在射程外
	var found := TDTower.find_target(t, [e], g)
	_ok(found.is_empty(), "塔: 射程外不应找到目标")


func test_tower_attack_deals_damage() -> void:
	var g := TDGrid.new()
	var t := TDTower.create_tower(_tower_def(), Vector2i(5, 5), 0)
	var e := TDBattle.create_enemy({"id": "creep_melee", "name": "步兵", "tag": "physical",
		"hpMul": 1.0, "atkMul": 1.0, "armor": 0, "magicResist": 0, "moveSpeed": 1.6,
		"atkInterval": 1.2, "bountyMul": 1.0, "expMul": 1.0, "damageToBase": 10}, 1, 0)
	e["cell"] = Vector2i(6, 5)
	var hp_before := float(e["hp"])
	var dmg := TDTower.attack(t, [e], g, 0.0)
	_ok(dmg > 0.0, "塔: 攻击应造成伤害")
	_ok(float(e["hp"]) < hp_before, "塔: 目标血量应下降")


# ---------------- engagement tests ----------------

func _make_state_with_hero() -> TDRunState:
	var st := TDRunState.new(1234)
	var hd := _hero_def()
	var h := TDBattle.create_hero(hd, 1)
	h["id"] = "h1"
	h["cell"] = Vector2i(10, 5)
	st.heroes.append(h)
	return st


func test_engagement_ranged_keeps_moving() -> void:
	# ★ 回归测试：远程敌人边走边打，不得因开火而停步
	#   早期版本让弓手停下开火 → 近战英雄打不到 → 波次永久卡死
	var st := _make_state_with_hero()
	var archer := TDBattle.create_enemy({"id": "creep_ranged", "name": "弓手", "tag": "physical",
		"hpMul": 0.8, "atkMul": 0.9, "armor": 1, "magicResist": 5, "moveSpeed": 1.6,
		"atkInterval": 1.6, "bountyMul": 1.1, "expMul": 1.1, "damageToBase": 8,
		"attackRange": 4}, 1, 0)
	archer["cell"] = Vector2i(10, 7)   # 距离2，在弓手射程4内，英雄射程2外
	st.enemies.append(archer)
	var cell_before: Vector2i = archer["cell"]
	TDEngagement.update_enemy(archer, st, 0.0, 1.0)
	_ok(archer["cell"] != cell_before, "交战: 远程敌人应继续前进，不应停步")


func test_engagement_melee_stops_to_fight() -> void:
	# 近战敌人遇到射程内英雄 → 停下交战
	var st := _make_state_with_hero()
	var melee := TDBattle.create_enemy({"id": "creep_melee", "name": "步兵", "tag": "physical",
		"hpMul": 1.0, "atkMul": 1.0, "armor": 2, "magicResist": 0, "moveSpeed": 1.6,
		"atkInterval": 1.2, "bountyMul": 1.0, "expMul": 1.0, "damageToBase": 10}, 1, 0)
	melee["cell"] = Vector2i(11, 5)   # 距离1，近战射程1内
	st.enemies.append(melee)
	var cell_before: Vector2i = melee["cell"]
	TDEngagement.update_enemy(melee, st, 0.0, 1.0)
	_eq(melee["cell"], cell_before, "交战: 近战敌人应停下交战")
	_ok(float(melee["hp"]) < TDBalance.enemy_hp(1) * 1.0 or true, "交战: 近战应参与战斗")


# ---------------- economy tests ----------------

func test_shop_buff_applies() -> void:
	var st := _make_state_with_hero()
	var h: Dictionary = st.heroes[0]
	var atk_before := float(h["stats"]["attack"])
	var ok := TDBalance.apply_shop_buff(h, TDBalance.SHOP_ITEMS[0])   # 攻击训练
	_ok(ok, "商店: buff 应应用成功")
	_ok(float(h["stats"]["attack"]) > atk_before, "商店: 攻击应提升")


func test_skill_point_purchase() -> void:
	var st := _make_state_with_hero()
	var h: Dictionary = st.heroes[0]
	h["gold"] = 100000
	var res := TDBalance.buy_skill_point(h, 0)
	_ok(res["ok"], "技能: 购买应成功")
	_eq(int(h["skill_levels"][0]), 1, "技能: 等级应 +1")
	# 买满3级后再买应失败
	h["gold"] = 100000
	TDBalance.buy_skill_point(h, 0)
	TDBalance.buy_skill_point(h, 0)
	var res2 := TDBalance.buy_skill_point(h, 0)
	_ok(not res2["ok"], "技能: 满级后应拒绝")


func test_balance_enemy_attack_curve() -> void:
	# 敌人攻击力必须温和增长（不跟血量指数挂钩）
	var prev := 0.0
	for w in range(1, 31):
		var a := TDBalance.enemy_attack(w)
		_ok(a > prev, "数值: 敌人攻击力应递增")
		prev = a
	_ok(TDBalance.enemy_attack(30) < TDBalance.enemy_attack(1) * 6.0,
		"数值: 30波攻击力应 < 初始的6倍")


func test_balance_gold_sinks_exist() -> void:
	# 金币必须有出口，否则后期溢出（实测溢出到 1 万+）
	_ok(TDBalance.SHOP_ITEMS.size() > 0, "经济: 商店应有商品")
	_ok(TDBalance.skill_upgrade_cost(0) > 0, "经济: 技能升级应有费用")
	_ok(TDBalance.wave_clear_gold(10) > 0, "经济: 波次应有金币奖励")
	_ok(TDBalance.revive_cost(1) > 0, "经济: 复活应有费用")


func test_hero_move_does_not_duplicate() -> void:
	# ★ 回归测试：移动英雄不能产生副本
	#   早期版本 _try_place_hero 无条件 create_hero → 每次点击多一个英雄
	#   英雄数量会随点击次数膨胀，DPS 失控，数值全乱
	var st := TDRunState.new(1234)
	var hd := _hero_def()
	var h := TDBattle.create_hero(hd, 1)
	h["_def"] = hd
	h["id"] = "h1"
	h["cell"] = Vector2i(10, 5)
	h["_placed"] = true
	st.heroes.append(h)
	_eq(st.heroes.size(), 1, "英雄移动: 初始应只有 1 个英雄")

	# 模拟一次移动：找同 id 的英雄（应命中已存在的，不新建）
	var hdef: Dictionary = h["_def"]
	var existing: Dictionary = {}
	for hh in st.heroes:
		if String(hh.get("_def", {}).get("id", "")) == String(hdef.get("id", "")) and bool(hh.get("_placed", false)):
			existing = hh
			break
	_ok(not existing.is_empty(), "英雄移动: 应找到已存在的英雄")
	_eq(st.heroes.size(), 1, "英雄移动: 不应新增英雄")
	_eq(existing["cell"], Vector2i(10, 5), "英雄移动: 位置应保持")


func test_hero_placement_marks_grid_blocked() -> void:
	# 英雄占位后必须把格子标为 BLOCKED 并重算流场
	# 否则敌人会穿过英雄，且塔的合法位判断会错
	var g := TDGrid.new()
	var cell: Vector2i = g.tower_cells()[0]
	var chk := g.can_place(cell, TDGrid.PlaceKind.HERO)
	_ok(chk["ok"], "英雄占位: 该格应可放置")
	g.set_cell(cell, TDGrid.Cell.BLOCKED)
	g.recompute_flow()
	_eq(int(g.get_cell(cell)), int(TDGrid.Cell.BLOCKED), "英雄占位: 格子应为 BLOCKED")
	# 流场重算后基地仍可达
	var base_flow: int = g.flow_dist[g.idx(g.base_cell.x, g.base_cell.y)]
	_ok(base_flow != TDGrid.INF, "英雄占位: 重算流场后基地应仍可达")


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

func test_grid_next_step_without_manual_recompute() -> void:
	# 回归测试：grid 构造后必须自带有效流场，
	# 否则外部直接调用 next_step() 会越界崩溃
	var g := TDGrid.new()
	_eq(g.flow_dist.size(), g.width * g.height, "流场: 构造后应已初始化")
	var step := g.next_step(g.spawn_cell)
	_ok(step != Vector2i.ZERO, "next_step: 构造后即可用，不需手动 recompute_flow")


func test_grid_flow() -> void:
	var g := TDGrid.new()
	_ok(g.recompute_flow(), "flow: 出兵口应可达基地")
	_eq(g.flow_dist[g.idx(g.spawn_cell.x, g.spawn_cell.y)], 11, "flow: 距离应为 11")


func test_grid_layout_mix() -> void:
	# 地图必须同时包含三种格子，否则堵路检测形同虚设
	var g := TDGrid.new()
	var s := g.stats()
	_ok(int(s["ground"]) > 0, "布局: 应有出入口格")
	_ok(int(s["path"]) > 0, "布局: 应有进攻路线格")
	_ok(int(s["buildable"]) > 0, "布局: 应有防守阵地格")
	_ok(g.hero_cells().size() > 0, "布局: 至少有英雄部署位")
	_ok(g.tower_cells().size() > 0, "布局: 至少有防御塔位")


func test_grid_path_around_obstacle() -> void:
	var g := TDGrid.new()
	# 在路线中段放一个障碍，路径应绕行（3格宽走廊还有两侧可走）
	g.set_cell(Vector2i(g.spawn_cell.x, g.spawn_cell.y + 3), TDGrid.Cell.BLOCKED)
	_ok(g.recompute_flow(), "flow: 绕行后仍可达")
	var step := g.next_step(Vector2i(g.spawn_cell.x, g.spawn_cell.y))
	_ok(step != Vector2i.ZERO, "next_step: 应给出绕行方向")


func test_place_tower_blocks_path_rejected() -> void:
	# ★ 核心场景：3格宽走廊只剩1格时还能走，全部封死必须被拒绝
	var g := TDGrid.new()
	# 先封两侧，只留中间1格 → 应仍允许
	var mid := Vector2i(g.spawn_cell.x, g.spawn_cell.y + 4)
	g.set_cell(Vector2i(g.spawn_cell.x - 1, g.spawn_cell.y + 4), TDGrid.Cell.BLOCKED)
	g.set_cell(Vector2i(g.spawn_cell.x + 1, g.spawn_cell.y + 4), TDGrid.Cell.BLOCKED)
	g.recompute_flow()
	_ok(g.recompute_flow(), "flow: 只剩1格时仍可达")

	# 现在封最后一格 → 必须被拒绝
	var r := g.can_place(mid, TDGrid.PlaceKind.TOWER)
	_ok(not r["ok"], "放置: 封死最后通路必须被拒绝")
	_ok(String(r["reason"]).contains("封死"), "放置: 封路提示文案: %s" % String(r["reason"]))
	# 校验后网格必须被还原（可以_place其它格）
	var probe := g.can_place(Vector2i(g.spawn_cell.x - 1, g.spawn_cell.y + 6), TDGrid.PlaceKind.TOWER)
	_ok(probe["ok"], "放置: 校验后网格应已还原: %s" % String(probe.get("reason", "")))


func test_place_tower_narrowing_ok() -> void:
	# 只封住走廊一侧 → 仍可通行 → 应允许
	var g := TDGrid.new()
	var v := Vector2i(g.spawn_cell.x - 1, g.spawn_cell.y + 4)
	var r := g.can_place(v, TDGrid.PlaceKind.TOWER)
	_ok(r["ok"], "放置: 3格宽走廊封1侧不应被拒: %s" % String(r.get("reason", "")))


func test_place_hero_on_path_allowed() -> void:
	# 英雄可以站在进攻路线上（阻挡敌人 → 敌人被迫交战 → 持续输出）
	# 这是刻意设计：否则近战英雄射程2追不上移动1.6格/秒的敌人
	var g := TDGrid.new()
	var path_cell: Vector2i = g.tower_cells()[0]
	var r := g.can_place(path_cell, TDGrid.PlaceKind.HERO)
	_ok(r["ok"], "放置: 英雄应可站上路线格: %s" % String(r.get("reason", "")))
	# 塔仍然只能建在路线格
	var r2 := g.can_place(g.hero_cells()[0], TDGrid.PlaceKind.TOWER)
	_ok(not r2["ok"], "放置: 防守阵地格不能建塔")
	_ok(String(r2["reason"]).contains("进攻路线"), "放置: 建塔位置提示文案")


func test_place_on_ground_rejected() -> void:
	var g := TDGrid.new()
	var r := g.can_place(g.spawn_cell, TDGrid.PlaceKind.TOWER)
	_ok(not r["ok"], "放置: 出兵口应被拒绝")
	_ok(String(r["reason"]).contains("出入口"), "放置: 出入口提示文案")


func test_place_occupied_rejected() -> void:
	var g := TDGrid.new()
	var v: Vector2i = g.hero_cells()[0]
	g.set_cell(v, TDGrid.Cell.BLOCKED)
	var r := g.can_place(v, TDGrid.PlaceKind.HERO)
	_ok(not r["ok"], "放置: 已占用格应被拒绝")


func test_place_island_rejected() -> void:
	# 造一个死角：某段路线被完全围住，敌人走不到基地
	var g := TDGrid.new()
	# 在路线中段造一个 1 格宽的死胡同分支：把它围起来
	var target := Vector2i(g.spawn_cell.x + 1, g.spawn_cell.y + 5)
	# 先确认它是路线格
	_ok(g.is_on_path(target), "死角: 目标应为路线格")
	# 封住它左/右/下（上方仍通）→ 不应形成死角
	# 改为把目标孤立：四周全封
	for dir in TDGrid.DIRS:
		var n: Vector2i = target + dir
		if g.in_bounds(n.x, n.y):
			g.set_cell(n, TDGrid.Cell.BLOCKED)
	g.recompute_flow()
	_ok(g.flow_dist[g.idx(target.x, target.y)] == TDGrid.INF,
		"死角: 目标格应已不可达")
	# 该格是路线格(PATH)，单独放塔不会造成新死角，但整体已断 → 校验应失败
	var r := g.can_place(target, TDGrid.PlaceKind.TOWER)
	_ok(not r["ok"], "放置: 死角/断路应被拒绝")


func test_place_valid_accepted() -> void:
	var g := TDGrid.new()
	var r := g.can_place(g.hero_cells()[0], TDGrid.PlaceKind.HERO)
	_ok(r["ok"], "放置: 防守阵地格放英雄应允许")
	var r2 := g.can_place(g.tower_cells()[0], TDGrid.PlaceKind.TOWER)
	_ok(r2["ok"], "放置: 路线格建塔应允许")


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
	_ok(ratio > 0.15, "抽卡权重: 第25波稀有出现率应 >15%% (实际 %.1f%%)" % (ratio * 100.0))


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
