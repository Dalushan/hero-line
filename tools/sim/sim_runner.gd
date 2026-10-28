extends SceneTree
## 无头数值模拟器
## 用法: godot --headless --script res://tools/sim/sim_runner.gd -- [runs] [seed]
##
## 目的：改数值不用手玩。用固定种子的简单 AI 托管跑 N 局，
##       输出通关波次分布 / 经济曲线 / 资源是否溢出，找出失衡点。

const HERO_DEF_PATH := "res://data/hero_def.json"
const ITEM_DEF_PATH := "res://data/item_def.json"
const ENEMY_DEF_PATH := "res://data/enemy_def.json"
const TOWER_DEF_PATH := "res://data/tower_def.json"

## 详细模式：第 3 个参数传 1 时打印逐波明细
static var VERBOSE := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs: int = int(args[0]) if args.size() > 0 else 100
	var base_seed: int = int(args[1]) if args.size() > 1 else 1000
	VERBOSE = args.size() > 2 and int(args[2]) == 1

	print("=== TD Hero Defense · Headless Balance Simulator ===")
	print("runs = %d, base_seed = %d" % [runs, base_seed])
	print("")

	var heroes_data := _load_defs(HERO_DEF_PATH, "heroes")
	var items_data := _load_defs(ITEM_DEF_PATH, "items")
	var enemies_data := _load_defs(ENEMY_DEF_PATH, "enemies")
	var towers_data := _load_defs(TOWER_DEF_PATH, "towers")

	if heroes_data.is_empty() or enemies_data.is_empty():
		print("FATAL: 无法加载数据表")
		quit(1)
		return

	var results: Array = []
	var t0 := Time.get_ticks_msec()

	for i in range(runs):
		var seed_value := base_seed + i
		var r := _simulate_one(seed_value, heroes_data, items_data, enemies_data, towers_data)
		results.append(r)

	var elapsed := Time.get_ticks_msec() - t0
	_report(results, elapsed, runs)
	quit(0)


# ---------------- 单局模拟 ----------------

func _simulate_one(seed_value: int, heroes_data: Array, items_data: Array, enemies_data: Array, towers_data: Array) -> Dictionary:
	var state := TDRunState.new(seed_value)
	var hero_defs := heroes_data.duplicate()
	var enemy_defs := enemies_data.duplicate()
	# 起始金币：否则开局买不起任何塔，经济系统形同虚设
	state.gold = 250
	state.add_gold(0)

	var wave_reached := 0
	var gold_curve: Array = []
	var deaths: Array = []

	for wave in range(1, TDBalance.waves_per_stage() + 1):
		state.wave = wave
		wave_reached = wave

		# --- 支援二选一 ---
		if TDWaveManager.has_support(wave):
			var cards := TDSupport.roll_cards(hero_defs, items_data, {
				"selected_hero_ids": state.selected_hero_ids, "wave": wave
			}, state.rng)
			if cards.size() > 0:
				# AI 选策略：优先稀有/传说，其次输出高
				var best := 0
				var best_score := -1.0
				for ci in range(cards.size()):
					var c: Dictionary = cards[ci]
					var score := 0.0
					match String(c.get("hero_rarity", "common")):
						"legendary": score = 100.0
						"rare": score = 70.0
						"common": score = 40.0
					score += float(c.get("item", {}).get("cost", 0)) / 50.0
					if score > best_score:
						best_score = score
						best = ci
				TDSupport.commit_selection(cards, best, {
					"selected_hero_ids": state.selected_hero_ids
				})
				# 选中的英雄加入战场（位置由 _ai_place_heroes 统一安排）
				var chosen: Dictionary = cards[best]
				var hdef := _find_by_id(hero_defs, String(chosen["hero_id"]))
				if not hdef.is_empty():
					var h := TDBattle.create_hero(hdef, 1)
					h["_def"] = hdef
					h["items"] = [chosen.get("item", {})]
					h["id"] = "h_%d" % state.heroes.size()
					state.heroes.append(h)

		# --- 开局：赠送 1 名初始英雄（否则前 4 波无防守，必然被平推） ---
		if wave == 1 and state.heroes.is_empty():
			var start_def := _find_by_id(hero_defs, "hero_zhan_guang")
			if not start_def.is_empty():
				var sh := TDBattle.create_hero(start_def, 1)
				sh["_def"] = start_def
				sh["id"] = "h_start"
				state.heroes.append(sh)

		# --- 布防 AI：填补空位 ---
		_ai_place_heroes(state, hero_defs)

		# --- 复活阵亡英雄（优先于建塔，否则金币全被塔吃掉，英雄永远死着） ---
		_ai_revive_heroes(state)

		# --- 波次间治疗（塔防标准约定：布防期回满血） ---
		for h in state.heroes:
			TDBattle.heal_between_waves(h)

		# --- 建塔 AI：有钱就买塔（必须有金币消耗，否则经济无意义） ---
		_ai_build_towers(state, towers_data)

		# --- 商店 AI：金币的主要出口（否则后期金币溢出到 1 万+） ---
		_ai_shop(state)

		# --- 冷却重置：t 是每波局部计时，跨波沿用冷却会让英雄开局沉默 ---
		for h in state.heroes:
			h["_next_atk"] = 0.0
			h["_move_accum"] = 0.0
		for tw in state.towers:
			tw["next_atk"] = 0.0

		# --- 波次编队 + 出怪 ---
		state.wave_groups = TDWaveManager.build_wave(wave, state.rng)
		state.pending_spawns.clear()
		for g in state.wave_groups:
			var gid := String(g["enemy_id"])
			var gdef := _find_by_id(enemy_defs, gid)
			if gdef.is_empty():
				continue
			for k in range(int(g["count"])):
				state.pending_spawns.append({
					"def": gdef,
					"at": float(g["delay"]) + float(k) * float(g["interval"]),
					"seed": k
				})
		# ★ 必须按出场时间排序：多组编队的 delay 不同，
		#   不排序会导致后面组的敌人一直排在数组尾部迟迟不出场
		state.pending_spawns.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))

		# --- 逐帧推进本波 ---
		var t := 0.0
		var dt := 0.1
		var spawn_idx := 0
		var max_time := 180.0
		var wave_kills := 0
		var wave_exp_total := 0
		# 性能：英雄表与存活表每波构建一次，避免每次击杀都重建
		var hero_by_id := {}
		for h in state.heroes:
			hero_by_id[String(h.get("id", ""))] = h
		var alive_map := state.hero_alive_map()

		while t < max_time:
			# 出怪
			while spawn_idx < state.pending_spawns.size() and float(state.pending_spawns[spawn_idx]["at"]) <= t:
				var sp: Dictionary = state.pending_spawns[spawn_idx]
				var e := TDBattle.create_enemy(sp["def"], wave, sp["seed"] + spawn_idx)
				e["cell"] = state.grid.spawn_cell
				state.enemies.append(e)
				spawn_idx += 1

			# 敌人推进 + 战斗（规则统一在 core/engagement.gd）
			var alive_enemies := 0
			for e in state.enemies:
				if not bool(e.get("alive", false)):
					continue
				alive_enemies += 1
				TDEngagement.update_enemy(e, state, t, dt)

			# 英雄攻击
			for h in state.heroes:
				TDEngagement.hero_attack(h, state, t)

			# 防御塔攻击
			for tw in state.towers:
				if t < float(tw.get("next_atk", 0.0)):
					continue
				tw["_now"] = t
				TDTower.attack(tw, state.enemies, state.grid, t)

			# 结算死亡
			var any_dead := false
			for e in state.enemies:
				if bool(e.get("alive", false)) or bool(e.get("_settled", false)):
					continue
				any_dead = true
				e["_settled"] = true
				if e.get("_reached_base", false):
					continue
				wave_kills += 1
				state.kills += 1
				var exp_res := TDExperience.settle_kill(
					e, String(e.get("last_hit_by", "")),
					alive_map, t)
				for hid in exp_res.keys():
					if String(hid) == "__pool__":
						continue
					var hero: Dictionary = hero_by_id.get(String(hid), {})
					if hero.is_empty():
						continue
					hero["exp"] = int(hero.get("exp", 0)) + int(exp_res[hid])
					wave_exp_total += int(exp_res[hid])
					TDBattle.check_level_up(hero)
				# 金币
				state.add_gold(int(e.get("bounty", 0)))

			# 清理死亡敌人（仅在有死亡时重建数组，避免每帧分配）
			if any_dead:
				state.enemies = state.enemies.filter(func(x): return bool(x.get("alive", false)) or not x.get("_settled", false))

			# 英雄生命回复
			for h in state.heroes:
				if not bool(h.get("alive", false)):
					continue
				var regen: float = float(h.get("stats", {}).get("hp_regen", 0.0))
				if regen > 0.0:
					var max_hp: float = float(h.get("stats", {}).get("max_hp", 1.0))
					h["hp"] = minf(max_hp, float(h.get("hp", 0.0)) + regen * dt)

			if state.is_game_over():
				break
			if alive_enemies == 0 and spawn_idx >= state.pending_spawns.size():
				break
			t += dt

		# 敌人清空但超时 = 打不过
		var cleared := true
		for e in state.enemies:
			if bool(e.get("alive", false)):
				cleared = false
				break

		gold_curve.append(state.gold)

		# 波次通关奖励（即使全灭也有收入，避免死亡螺旋）
		state.add_gold(TDBalance.wave_clear_gold(wave))
		# 基地修复（漏怪可挽回，但有上限）
		state.base_hp = mini(state.base_hp_max, state.base_hp + TDBalance.base_repair(wave))

		if VERBOSE:
			var hp_pct := 100.0 * float(state.base_hp) / float(state.base_hp_max)
			var dps := state.total_hero_dps()
			var hpos := ""
			for h in state.heroes:
				var hc: Vector2i = h.get("cell", Vector2i.ZERO)
				hpos += "[%s@(%d,%d) rng%.1f hp%.0f] " % [
					String(h.get("name", "?")), hc.x, hc.y,
					float(h.get("stats", {}).get("attack_range", 0.0)),
					float(h.get("hp", 0.0))]
			print("  wave %2d | 组%2d 击杀%3d | 塔%2d | HP%5.1f%% | 金币%4d | %s"
				% [wave, state.wave_groups.size(), wave_kills, state.towers.size(),
				   hp_pct, state.gold, hpos])

		if state.is_game_over():
			deaths.append(wave)
			return {
				"seed": seed_value,
				"victory": false,
				"wave_reached": wave,
				"base_hp": state.base_hp,
				"gold": state.gold,
				"gold_curve": gold_curve,
				"heroes": state.heroes.size(),
				"kills": state.kills,
				"deaths": deaths,
			}
		if not cleared:
			deaths.append(wave)
			# 诊断：把卡住的敌人位置打印出来，便于定位寻路死锁
			if VERBOSE:
				var stuck := []
				for e in state.enemies:
					if bool(e.get("alive", false)):
						var ec: Vector2i = e.get("cell", Vector2i.ZERO)
						var fd: int = state.grid.flow_dist[state.grid.idx(ec.x, ec.y)] if state.grid.flow_dist.size() == state.grid.width * state.grid.height else -1
						stuck.append("%s@(%d,%d) flow=%d" % [String(e.get("name","?")), ec.x, ec.y, fd])
				print("  [TIMEOUT wave %d] 卡住敌人 %d 个: %s" % [wave, stuck.size(), str(stuck).substr(0, 400)])
			return {
				"seed": seed_value,
				"victory": false,
				"wave_reached": wave,
				"base_hp": state.base_hp,
				"gold": state.gold,
				"gold_curve": gold_curve,
				"heroes": state.heroes.size(),
				"kills": state.kills,
				"deaths": deaths,
				"reason": "timeout",
			}

		state.waves_cleared += 1

	return {
		"seed": seed_value,
		"victory": true,
		"wave_reached": TDBalance.waves_per_stage(),
		"base_hp": state.base_hp,
		"gold": state.gold,
		"gold_curve": gold_curve,
		"heroes": state.heroes.size(),
		"kills": state.kills,
		"deaths": deaths,
	}


# ---------------- AI 辅助 ----------------

func _ai_build_towers(state: TDRunState, towers_data: Array) -> void:
	# AI 建塔/升级：
	#  1) 有空位就造新塔
	#  2) 没有空位或金币溢出时升级已有塔 —— 否则金币毫无用处，后期必然溢出
	if towers_data.is_empty():
		return
	var guard_iter := 0
	while guard_iter < 200:
		guard_iter += 1
		# 优先升级（前期塔位有限，升级比新塔划算）
		var upgrade_target := _cheapest_upgradable_tower(state)
		if not upgrade_target.is_empty():
			var cost := TDTower.upgrade_cost(upgrade_target)
			if state.gold >= cost:
				state.gold -= cost
				TDTower.upgrade_tower(upgrade_target)
				continue
		# 否则造新塔
		var pick := _cheapest_affordable_tower(state, towers_data)
		if pick.is_empty():
			return
		var cell := _best_tower_cell(state)
		if cell == Vector2i(-1, -1):
			return
		var tower := TDTower.create_tower(pick, cell, state.towers.size())
		state.towers.append(tower)
		state.grid.set_cell(cell, TDGrid.Cell.BLOCKED)
		state.grid.recompute_flow()   # ★ 占位后必须重算流场，否则敌人仍会穿过塔
		state.gold -= int(pick.get("cost", 0))


func _cheapest_upgradable_tower(state: TDRunState) -> Dictionary:
	var best := {}
	var best_cost := 999999
	for t in state.towers:
		if int(t.get("level", 1)) >= TDTower.MAX_LEVEL:
			continue
		var c := TDTower.upgrade_cost(t)
		if c < best_cost:
			best_cost = c
			best = t
	return best


func _cheapest_affordable_tower(state: TDRunState, towers_data: Array) -> Dictionary:
	var best := {}
	var best_cost := 999999
	for t in towers_data:
		var c := int(t.get("cost", 0))
		if c <= state.gold and c < best_cost:
			best_cost = c
			best = t
	return best


func _best_tower_cell(state: TDRunState) -> Vector2i:
	# 塔位：路线格，且要离已有塔远一些（覆盖全路线而不是堆在一处）
	var cells := state.grid.tower_cells()
	if cells.is_empty():
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for c in cells:
		if not state.grid.can_place(c, TDGrid.PlaceKind.TOWER)["ok"]:
			continue
		# 分数：到已有塔的最小距离（越大越好）
		var min_dist := 9999.0
		for t in state.towers:
			var tc: Vector2i = t.get("cell", Vector2i.ZERO)
			var d := float(abs(tc.x - c.x) + abs(tc.y - c.y))
			min_dist = minf(min_dist, d)
		if state.towers.is_empty():
			min_dist = 10.0
		if min_dist > best_score:
			best_score = min_dist
			best = c
	return best


func _ai_shop(state: TDRunState) -> void:
	# 商店是金币的主要出口。AI：优先买攻击/攻速类 buff 提升 DPS
	if state.heroes.is_empty():
		return
	# 刷新 3 件候选
	var mult := TDBalance.shop_price_mult(state.wave)
	var pool := TDBalance.SHOP_ITEMS.duplicate()
	pool.shuffle()
	var offers: Array = []
	for i in range(mini(3, pool.size())):
		var it: Dictionary = pool[i].duplicate()
		it["cost"] = int(round(float(it.get("cost", 100)) * mult))
		offers.append(it)
	state.shop_offers = offers

	# 买得起就买：优先给 DPS 最高的英雄加攻击
	for it in offers:
		var cost := int(it.get("cost", 0))
		if state.gold < cost:
			continue
		# 选一个存活英雄（优先输出最高的）
		var target := _best_hero(state)
		if target.is_empty():
			break
		state.gold -= cost
		TDBalance.apply_shop_buff(target, it)
		state.gold_spent += cost

	# 金币还有富余 → 买技能点（Dota2 风格，最自然的金币出口）
	_ai_buy_skills(state)


func _ai_buy_skills(state: TDRunState) -> void:
	# 给存活英雄买技能点。技能是英雄的主要成长来源之一。
	# 走 TDBalance.buy_skill_point() 正式接口 —— 它用 hero["gold"] 结算，
	# 所以这里把 state.gold 同步给英雄再扣回，保持单一金币池。
	for h in state.heroes:
		if not bool(h.get("alive", false)):
			continue
		var skills: Array = h.get("skill_levels", [0, 0, 0, 0])
		for si in range(skills.size()):
			var cur: int = int(skills[si])
			if cur >= 3:
				continue
			var cost := TDBalance.skill_upgrade_cost(cur)
			if state.gold < cost:
				return
			h["gold"] = state.gold
			var res := TDBalance.buy_skill_point(h, si)
			if not res["ok"]:
				state.gold = int(h.get("gold", 0))
				return
			state.gold = int(h.get("gold", 0))
			state.gold_spent += cost


func _best_hero(state: TDRunState) -> Dictionary:
	var best := {}
	var best_dps := -1.0
	for h in state.heroes:
		if not bool(h.get("alive", false)):
			continue
		var st: Dictionary = h.get("stats", {})
		var dps := float(st.get("attack", 0.0)) / maxf(float(st.get("atk_interval", 1.0)), 0.1)
		if dps > best_dps:
			best_dps = dps
			best = h
	return best


func _ai_revive_heroes(state: TDRunState) -> void:
	# 英雄阵亡后复活（花金币），否则中后期 DPS 归零必然崩盘
	for h in state.heroes:
		if bool(h.get("alive", false)):
			continue
		var revive_cost := TDBalance.revive_cost(int(h.get("level", 1)))
		if state.gold < revive_cost:
			continue
		state.gold -= revive_cost
		h["alive"] = true
		var max_hp: float = float(h.get("stats", {}).get("max_hp", 100.0))
		h["hp"] = max_hp * 0.6
		# 复活后需要重新占位
		h["_placed"] = false


func _ai_place_heroes(state: TDRunState, hero_defs: Array) -> void:
	# 英雄优先站上进攻路线（挡住敌人 → 敌人被迫交战 → 英雄持续输出）
	# 次选紧贴路线的防守阵地格（射程内可打到）
	var unplaced: Array = []
	for h in state.heroes:
		if not bool(h.get("_placed", false)):
			unplaced.append(h)
	if unplaced.is_empty():
		return

	var path_cells := state.grid.tower_cells()      # PATH 格（可站英雄）
	var zone_cells := state.grid.hero_cells()       # BUILDABLE 格（空地）
	# 空地按到路线距离排序：越近越好
	zone_cells.sort_custom(func(a, b): return state.grid.dist_to_path(a) < state.grid.dist_to_path(b))
	# ★ 路线格按"距基地还有多远"降序：flow 越大 = 离基地越远 = 越靠前
	#   英雄要站在敌人来的方向（靠前），站在基地后面等于没有防守
	path_cells.sort_custom(func(a, b):
		return state.grid.flow_dist[state.grid.idx(a.x, a.y)] > state.grid.flow_dist[state.grid.idx(b.x, b.y)])

	var placed_count := 0
	for h in unplaced:
		var chosen := Vector2i(-1, -1)
		# 70% 站路线，30% 站贴路线空地
		var prefer_path := (placed_count % 10) < 7
		if prefer_path:
			for c in path_cells:
				var chk := state.grid.can_place(c, TDGrid.PlaceKind.HERO)
				if chk["ok"]:
					chosen = c
					break
		if chosen == Vector2i(-1, -1):
			for c in zone_cells:
				var chk2 := state.grid.can_place(c, TDGrid.PlaceKind.HERO)
				if chk2["ok"]:
					chosen = c
					break
		if chosen == Vector2i(-1, -1):
			continue
		h["cell"] = chosen
		h["_placed"] = true
		state.grid.set_cell(chosen, TDGrid.Cell.BLOCKED)
		state.grid.recompute_flow()   # ★ 占位后必须重算流场
		placed_count += 1


func _pick_placement(grid: TDGrid, salt: int) -> Vector2i:
	var cells := grid.hero_cells()
	if cells.is_empty():
		return Vector2i(-1, -1)
	# 按到通路距离排序，取最近的几个轮换
	var sorted_cells := cells.duplicate()
	sorted_cells.sort_custom(func(a, b): return grid.dist_to_path(a) < grid.dist_to_path(b))
	var idx: int = (salt * 3) % sorted_cells.size()
	var candidate: Vector2i = sorted_cells[idx]
	var r := grid.can_place(candidate, TDGrid.PlaceKind.HERO)
	if not r["ok"]:
		return Vector2i(-1, -1)
	return candidate


func _nearest_hero_in_range(state: TDRunState, enemy: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1e9
	var rng: float = float(enemy.get("attack_range", 1))
	for h in state.heroes:
		if not bool(h.get("alive", false)):
			continue
		var d: float = _cell_dist(enemy["cell"], h["cell"])
		if d <= rng and d < best_d:
			best_d = d
			best = h
	return best


func _nearest_enemy_in_range(state: TDRunState, hero: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1e9
	var rng: float = float(hero.get("stats", {}).get("attack_range", 2))
	for e in state.enemies:
		if not bool(e.get("alive", false)):
			continue
		var d: float = _cell_dist(hero["cell"], e["cell"])
		if d <= rng and d < best_d:
			best_d = d
			best = e
	return best


func _cell_dist(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))


func _find_by_id(arr: Array, id: String) -> Dictionary:
	for x in arr:
		if String(x.get("id", "")) == id:
			return x
	return {}


func _load_defs(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("数据文件不存在: " + path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or not (parsed is Dictionary):
		push_error("JSON 解析失败: " + path)
		return []
	return parsed.get(key, [])


# ---------------- 报告 ----------------

func _report(results: Array, elapsed_ms: int, runs: int) -> void:
	var victories := 0
	var wave_sum := 0
	var gold_sum := 0
	var hp_sum := 0
	var hero_sum := 0
	var wave_hist := {}

	for r in results:
		if bool(r.get("victory", false)):
			victories += 1
		wave_sum += int(r.get("wave_reached", 0))
		gold_sum += int(r.get("gold", 0))
		hp_sum += int(r.get("base_hp", 0))
		hero_sum += int(r.get("heroes", 0))
		var w := int(r.get("wave_reached", 0))
		wave_hist[w] = int(wave_hist.get(w, 0)) + 1

	print("--- 结果汇总 (%d 局, 用时 %d ms) ---" % [runs, elapsed_ms])
	print("通关率      : %d/%d = %.1f%%" % [victories, runs, float(victories) / maxf(float(runs), 1.0) * 100.0])
	print("平均到达波次: %.1f / %d" % [float(wave_sum) / maxf(float(runs), 1.0), TDBalance.waves_per_stage()])
	print("平均最终金币: %d" % int(float(gold_sum) / maxf(float(runs), 1.0)))
	print("平均剩余基地HP: %.0f / 1000" % (float(hp_sum) / maxf(float(runs), 1.0)))
	print("平均英雄数  : %.1f" % (float(hero_sum) / maxf(float(runs), 1.0)))
	print("")

	print("--- 到达波次分布 ---")
	var keys := wave_hist.keys()
	keys.sort()
	for k in keys:
		var count: int = wave_hist[k]
		var bar := ""
		var n := int(count / maxf(float(runs) / 40.0, 1.0))
		for _i in range(mini(n, 40)):
			bar += "█"
		print("  第 %2d 波: %3d  %s" % [k, count, bar])

	print("")
	print("--- 金币曲线 (首局) ---")
	if results.size() > 0:
		var curve: Array = results[0].get("gold_curve", [])
		for i in range(0, curve.size(), 5):
			print("  wave %2d: %d gold" % [i + 1, curve[i]])

	print("")
	# 平衡提示
	var win_rate := float(victories) / maxf(float(runs), 1.0)
	if win_rate > 0.95:
		print("⚠  平衡提示: 通关率 >95%，难度偏低，建议提高小兵血量或降低初始资源")
	elif win_rate < 0.15:
		print("⚠  平衡提示: 通关率 <15%，难度过高，建议降低小兵血量或增强初始英雄")
	else:
		print("✓ 平衡提示: 通关率 %.1f%% 处于合理区间 (15%%~95%%)" % (win_rate * 100.0))
