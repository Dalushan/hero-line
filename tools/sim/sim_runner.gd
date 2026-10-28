extends SceneTree
## 无头数值模拟器
## 用法: godot --headless --script res://tools/sim/sim_runner.gd -- [runs] [seed]
##
## 目的：改数值不用手玩。用固定种子的简单 AI 托管跑 N 局，
##       输出通关波次分布 / 经济曲线 / 资源是否溢出，找出失衡点。

const HERO_DEF_PATH := "res://data/hero_def.json"
const ITEM_DEF_PATH := "res://data/item_def.json"
const ENEMY_DEF_PATH := "res://data/enemy_def.json"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs: int = int(args[0]) if args.size() > 0 else 100
	var base_seed: int = int(args[1]) if args.size() > 1 else 1000

	print("=== TD Hero Defense · Headless Balance Simulator ===")
	print("runs = %d, base_seed = %d" % [runs, base_seed])
	print("")

	var heroes_data := _load_defs(HERO_DEF_PATH, "heroes")
	var items_data := _load_defs(ITEM_DEF_PATH, "items")
	var enemies_data := _load_defs(ENEMY_DEF_PATH, "enemies")

	if heroes_data.is_empty() or enemies_data.is_empty():
		print("FATAL: 无法加载数据表")
		quit(1)
		return

	var results: Array = []
	var t0 := Time.get_ticks_msec()

	for i in range(runs):
		var seed_value := base_seed + i
		var r := _simulate_one(seed_value, heroes_data, items_data, enemies_data)
		results.append(r)

	var elapsed := Time.get_ticks_msec() - t0
	_report(results, elapsed, runs)


# ---------------- 单局模拟 ----------------

func _simulate_one(seed_value: int, heroes_data: Array, items_data: Array, enemies_data: Array) -> Dictionary:
	var state := TDRunState.new(seed_value)
	var hero_defs := heroes_data.duplicate()
	var enemy_defs := enemies_data.duplicate()

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
				# 选中的英雄加入战场
				var chosen: Dictionary = cards[best]
				var hdef := _find_by_id(hero_defs, String(chosen["hero_id"]))
				if not hdef.is_empty():
					var h := TDBattle.create_hero(hdef, 1)
					h["_def"] = hdef
					h["items"] = [chosen.get("item", {})]
					h["id"] = "h_%d" % state.heroes.size()
					# 布防到离通路最近的建造格
					var spot := _pick_placement(state.grid, state.heroes.size())
					h["cell"] = spot
					state.grid.set_cell(spot, TDGrid.Cell.BLOCKED)
					state.heroes.append(h)

		# --- 布防 AI：填补空位 ---
		_ai_place_heroes(state, hero_defs)

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

		# --- 逐帧推进本波 ---
		var t := 0.0
		var dt := 0.1
		var spawn_idx := 0
		var max_time := 180.0
		var wave_kills := 0
		var wave_exp_total := 0

		while t < max_time:
			# 出怪
			while spawn_idx < state.pending_spawns.size() and float(state.pending_spawns[spawn_idx]["at"]) <= t:
				var sp: Dictionary = state.pending_spawns[spawn_idx]
				var e := TDBattle.create_enemy(sp["def"], wave, sp["seed"] + spawn_idx)
				e["cell"] = state.grid.spawn_cell
				state.enemies.append(e)
				spawn_idx += 1

			# 敌人推进 + 战斗
			var alive_enemies := 0
			for e in state.enemies:
				if not bool(e.get("alive", false)):
					continue
				alive_enemies += 1
				# 找射程内最近英雄
				var target := _nearest_hero_in_range(state, e)
				if not target.is_empty():
					# 敌人攻击英雄
					var atk_cd: float = float(e.get("atk_interval", 1.5))
					e["_next_atk"] = float(e.get("_next_atk", t))
					if t >= float(e["_next_atk"]):
						TDBattle.enemy_attack_hero(e, target)
						e["_next_atk"] = t + atk_cd
					continue

				# 移动
				var step := state.grid.next_step(e["cell"])
				if step == Vector2i.ZERO:
					# 到基地了
					state.damage_base(int(e.get("damage_to_base", 10)))
					e["alive"] = false
					e["_reached_base"] = true
					continue
				e["cell"] = e["cell"] + step
				e["_next_atk"] = float(e.get("_next_atk", t))

			# 英雄攻击
			for h in state.heroes:
				if not bool(h.get("alive", false)):
					continue
				var atk_cd: float = float(h.get("stats", {}).get("atk_interval", 1.0))
				h["_next_atk"] = float(h.get("_next_atk", 0.0))
				if t < float(h["_next_atk"]):
					continue
				var tgt := _nearest_enemy_in_range(state, h)
				if tgt.is_empty():
					h["_next_atk"] = t + 0.1
					continue
				TDBattle.hero_attack_enemy(h, tgt, t)
				h["_next_atk"] = t + atk_cd

			# 结算死亡
			for e in state.enemies:
				if bool(e.get("alive", false)) or e.get("_settled", false):
					continue
				if e.get("_reached_base", false):
					e["_settled"] = true
					continue
				e["_settled"] = true
				wave_kills += 1
				state.kills += 1
				var exp_res := TDExperience.settle_kill(
					e, String(e.get("last_hit_by", "")),
					state.hero_alive_map(), t)
				for hid in exp_res.keys():
					if hid == "__pool__":
						continue
					var hero := state.find_hero(String(hid))
					if hero.is_empty():
						continue
					hero["exp"] = int(hero.get("exp", 0)) + int(exp_res[hid])
					wave_exp_total += int(exp_res[hid])
					TDBattle.check_level_up(hero)
				# 金币
				state.add_gold(int(e.get("bounty", 0)))

			# 清理死亡敌人
			state.enemies = state.enemies.filter(func(x): return bool(x.get("alive", false)) or not x.get("_settled", false))

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

func _ai_place_heroes(state: TDRunState, hero_defs: Array) -> void:
	# 把未放置的英雄放到离通路最近的可用建造格
	for h in state.heroes:
		if String(h.get("cell", Vector2i(-1, -1))) != str(Vector2i(-1, -1)):
			continue
		var spot := _pick_placement(state.grid, state.heroes.size())
		if spot == Vector2i(-1, -1):
			continue
		h["cell"] = spot
		state.grid.set_cell(spot, TDGrid.Cell.BLOCKED)


func _pick_placement(grid: TDGrid, salt: int) -> Vector2i:
	var cells := grid.buildable_cells()
	if cells.is_empty():
		return Vector2i(-1, -1)
	# 按到通路距离排序，取最近的几个轮换
	var sorted_cells := cells.duplicate()
	sorted_cells.sort_custom(func(a, b): return grid.dist_to_path(a) < grid.dist_to_path(b))
	var idx: int = (salt * 3) % sorted_cells.size()
	var candidate: Vector2i = sorted_cells[idx]
	var r := grid.can_place(candidate)
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
