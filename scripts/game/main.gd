extends Node
## 主控制器：驱动 core 层的状态机，把状态推给渲染层。
## 关键：所有规则判定在 core，这里只做"调度 + 转发事件"。

const HERO_DEF_PATH := "res://data/hero_def.json"
const ITEM_DEF_PATH := "res://data/item_def.json"
const ENEMY_DEF_PATH := "res://data/enemy_def.json"
const TOWER_DEF_PATH := "res://data/tower_def.json"

var state: TDRunState
var battlefield: Node2D
var support_panel: Control
var build_bar: Control

var _heroes_data: Array = []
var _items_data: Array = []
var _enemies_data: Array = []
var _towers_data: Array = []
var _enemy_def_map: Dictionary = {}
var _tower_def_map: Dictionary = {}

var _wave_timer := 0.0
var _spawn_queue: Array = []
var _spawn_idx := 0
var _time := 0.0
var _enemy_nodes: Array = []
var _hero_nodes: Dictionary = {}
var _tower_nodes: Dictionary = {}


func _ready() -> void:
	_load_data()
	battlefield = get_node_or_null("Battlefield")
	support_panel = get_node_or_null("SupportPanel")
	build_bar = get_node_or_null("BuildBar")
	if battlefield:
		battlefield.cell_clicked.connect(_on_cell_clicked)
		battlefield.cell_hovered.connect(_on_cell_hovered)
	if build_bar:
		build_bar.tower_selected.connect(_on_tower_selected)
		build_bar.upgrade_selected.connect(_on_upgrade_selected)
		build_bar.cancel_selected.connect(_on_cancel_selected)
	_start_new_run()


func _on_tower_selected(tower_def: Dictionary) -> void:
	# 选了塔 → 进入建塔模式，等玩家点格子
	if state.gold < int(tower_def.get("cost", 0)):
		return
	battlefield.set_build_tower(tower_def)


func _on_upgrade_selected() -> void:
	battlefield.set_upgrade_mode()


func _on_cancel_selected() -> void:
	battlefield.clear_build_mode()


func _on_cell_hovered(_cell: Vector2i, _kind: int, _ok: bool, _reason: String) -> void:
	pass


func _on_cell_clicked(cell: Vector2i, kind: int) -> void:
	match kind:
		battlefield.BuildMode.TOWER:
			_try_build_tower(cell)
		battlefield.BuildMode.UPGRADE:
			_try_upgrade_tower(cell)
		battlefield.BuildMode.HERO:
			_try_place_hero(cell)
		_:
			pass


func _try_build_tower(cell: Vector2i) -> void:
	var tdef: Dictionary = battlefield.pending_tower_def
	if tdef.is_empty():
		return
	var cost := int(tdef.get("cost", 0))
	if state.gold < cost:
		return
	# 合法性判定在 core
	var chk := state.grid.can_place(cell, TDGrid.PlaceKind.TOWER)
	if not chk["ok"]:
		return
	var tower := TDTower.create_tower(tdef, cell, state.towers.size())
	state.towers.append(tower)
	state.grid.set_cell(cell, TDGrid.Cell.BLOCKED)
	state.grid.recompute_flow()   # ★ 占位后必须重算流场
	state.gold -= cost
	_spawn_tower_node(tower)


func _try_upgrade_tower(cell: Vector2i) -> void:
	for t in state.towers:
		var tc: Vector2i = t.get("cell", Vector2i.ZERO)
		if tc != cell:
			continue
		if int(t.get("level", 1)) >= TDTower.MAX_LEVEL:
			return
		var cost := TDTower.upgrade_cost(t)
		if state.gold < cost:
			return
		state.gold -= cost
		TDTower.upgrade_tower(t)
		return


func _try_place_hero(cell: Vector2i) -> void:
	var hdef: Dictionary = battlefield.pending_hero_def
	if hdef.is_empty():
		return
	var chk := state.grid.can_place(cell, TDGrid.PlaceKind.HERO)
	if not chk["ok"]:
		return
	var h := TDBattle.create_hero(hdef, 1)
	h["_def"] = hdef
	h["id"] = "h_%d" % state.heroes.size()
	h["cell"] = cell
	h["_placed"] = true
	state.grid.set_cell(cell, TDGrid.Cell.BLOCKED)
	state.grid.recompute_flow()
	state.heroes.append(h)
	_spawn_hero_node(h)


func _load_data() -> void:
	_heroes_data = _load_json_array(HERO_DEF_PATH, "heroes")
	_items_data = _load_json_array(ITEM_DEF_PATH, "items")
	var enemies := _load_json_array(ENEMY_DEF_PATH, "enemies")
	_enemies_data = enemies
	for e in enemies:
		_enemy_def_map[String(e.get("id", ""))] = e
	var towers := _load_json_array(TOWER_DEF_PATH, "towers")
	_towers_data = towers
	for t in towers:
		_tower_def_map[String(t.get("id", ""))] = t


func _load_json_array(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("数据文件不存在: " + path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed.get(key, [])
	return []


func _start_new_run() -> void:
	state = TDRunState.new(TDRng.make_random_seed())
	state.base_hp_max = 1000
	state.base_hp = 1000
	state.gold = 250
	# 开局赠送 1 名初始英雄（否则前 4 波无防守，必然被平推）
	var start_def := _find_hero_def("hero_zhan_guang")
	if not start_def.is_empty():
		var h := TDBattle.create_hero(start_def, 1)
		h["_def"] = start_def
		h["id"] = "h_start"
		state.heroes.append(h)
	if battlefield and battlefield.has_method("setup"):
		battlefield.setup(state)
	_begin_prepare()


func _begin_prepare() -> void:
	state.advance_phase(TDRunState.Phase.PREPARING)
	_wave_timer = TDBalance.wave_interval()
	# 波次间治疗（塔防标准约定）
	for h in state.heroes:
		TDBattle.heal_between_waves(h)
	# 冷却重置（_time 是全局时间，但每波开始应让单位立即可行动）
	for h in state.heroes:
		h["_next_atk"] = 0.0
	for tw in state.towers:
		tw["next_atk"] = 0.0
	# 自动布防（初始英雄）+ 玩家手动建塔
	_auto_place_heroes()
	_refresh_shop()
	if build_bar and build_bar.has_method("setup"):
		build_bar.setup(state, _towers_data)


func _auto_place_heroes() -> void:
	# 英雄优先站进攻路线（挡住敌人 → 敌人被迫交战 → 持续输出）
	for h in state.heroes:
		if bool(h.get("_placed", false)):
			continue
		var spot := _pick_placement()
		if spot == Vector2i(-1, -1):
			continue
		h["cell"] = spot
		h["_placed"] = true
		state.grid.set_cell(spot, TDGrid.Cell.BLOCKED)
		state.grid.recompute_flow()
		_spawn_hero_node(h)


func _auto_build_towers() -> void:
	# AI 建塔：买得起的最便宜塔
	var guard := 0
	while guard < 50:
		guard += 1
		var pick := {}
		var best_cost := 999999
		for t in _towers_data:
			var c := int(t.get("cost", 0))
			if c <= state.gold and c < best_cost:
				best_cost = c
				pick = t
		if pick.is_empty():
			return
		var cell := _pick_tower_cell()
		if cell == Vector2i(-1, -1):
			return
		var tower := TDTower.create_tower(pick, cell, state.towers.size())
		state.towers.append(tower)
		state.grid.set_cell(cell, TDGrid.Cell.BLOCKED)
		state.grid.recompute_flow()
		state.gold -= int(pick.get("cost", 0))
		_spawn_tower_node(tower)


func _refresh_shop() -> void:
	var mult := TDBalance.shop_price_mult(state.wave)
	var pool := TDBalance.SHOP_ITEMS.duplicate()
	pool.shuffle()
	var offers: Array = []
	for i in range(mini(3, pool.size())):
		var it: Dictionary = pool[i].duplicate()
		it["cost"] = int(round(float(it.get("cost", 100)) * mult))
		offers.append(it)
	state.shop_offers = offers


func _begin_wave() -> void:
	state.wave += 1
	state.advance_phase(TDRunState.Phase.RUNNING)
	state.wave_groups = TDWaveManager.build_wave(state.wave, state.rng)
	print("[wave %d] 开始 | 英雄 %d | 塔 %d | 金币 %d | 基地HP %d" % [
		state.wave, state.heroes.size(), state.towers.size(), state.gold, state.base_hp])
	_spawn_queue.clear()
	_spawn_idx = 0
	for g in state.wave_groups:
		var gid := String(g.get("enemy_id", ""))
		var gdef = _enemy_def_map.get(gid, {})
		if gdef.is_empty():
			continue
		for k in range(int(g.get("count", 0))):
			_spawn_queue.append({
				"def": gdef,
				"at": float(g.get("delay", 0.0)) + float(k) * float(g.get("interval", 1.0)),
				"seed": k,
			})
	# ★ 必须按出场时间排序：多组编队 delay 不同，不排序会卡住出怪
	_spawn_queue.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))


func _process(delta: float) -> void:
	if state == null:
		return
	_time += delta

	match state.phase:
		TDRunState.Phase.PREPARING:
			_wave_timer -= delta
			if _wave_timer <= 0.0:
				_begin_wave()
		TDRunState.Phase.DRAFTING:
			pass   # 等待玩家选择
		TDRunState.Phase.RUNNING:
			_tick_running(delta)
		_:
			pass


func _tick_running(delta: float) -> void:
	# 出怪
	while _spawn_idx < _spawn_queue.size() and float(_spawn_queue[_spawn_idx]["at"]) <= _time:
		var sp: Dictionary = _spawn_queue[_spawn_idx]
		var e := TDBattle.create_enemy(sp["def"], state.wave, sp["seed"] + _spawn_idx)
		e["cell"] = state.grid.spawn_cell
		state.enemies.append(e)
		_spawn_enemy_node(e)
		_spawn_idx += 1

	# 敌人推进（规则统一在 core/engagement.gd）
	for e in state.enemies:
		if not bool(e.get("alive", false)):
			continue
		var st := TDEngagement.update_enemy(e, state, _time, delta)
		if st == TDEngagement.STATUS_REACHED_BASE:
			_remove_enemy_node(e)
			if state.is_game_over():
				_on_defeat()
				return
		else:
			_move_enemy_node(e)

	# 英雄攻击
	for h in state.heroes:
		TDEngagement.hero_attack(h, state, _time)

	# 防御塔攻击
	for tw in state.towers:
		if _time < float(tw.get("next_atk", 0.0)):
			continue
		tw["_now"] = _time
		TDTower.attack(tw, state.enemies, state.grid, _time)

	# 结算死亡
	_settle_deaths()

	# 波次结束判断
	if _spawn_idx >= _spawn_queue.size():
		var any_alive := false
		for e in state.enemies:
			if bool(e.get("alive", false)):
				any_alive = true
				break
		if not any_alive:
			_on_wave_cleared()


func _settle_deaths() -> void:
	var alive_map := state.hero_alive_map()
	for e in state.enemies:
		if bool(e.get("alive", false)) or bool(e.get("_settled", false)):
			continue
		e["_settled"] = true
		state.kills += 1
		var res := TDExperience.settle_kill(e, String(e.get("last_hit_by", "")), alive_map, _time)
		for hid in res.keys():
			if String(hid) == "__pool__":
				continue
			var hero := state.find_hero(String(hid))
			if hero.is_empty():
				continue
			hero["exp"] = int(hero.get("exp", 0)) + int(res[hid])
			TDBattle.check_level_up(hero)
		state.add_gold(int(e.get("bounty", 0)))
		_remove_enemy_node(e)


func _on_wave_cleared() -> void:
	state.waves_cleared += 1
	state.advance_phase(TDRunState.Phase.SETTLING)
	if state.wave >= TDBalance.waves_per_stage():
		_on_victory()
		return
	# 下一波之前触发支援二选一
	if TDWaveManager.has_support(state.wave + 1):
		_open_draft()
	else:
		_begin_prepare()


func _open_draft() -> void:
	state.advance_phase(TDRunState.Phase.DRAFTING)
	var cards := TDSupport.roll_cards(_heroes_data, _items_data, {
		"selected_hero_ids": state.selected_hero_ids,
		"wave": state.wave + 1,
	}, state.rng)
	state.support_cards = cards
	if support_panel:
		support_panel.visible = true
		support_panel.setup(cards)
		support_panel.card_chosen.connect(_on_card_chosen)


func _on_card_chosen(index: int) -> void:
	if support_panel:
		support_panel.visible = false
	TDSupport.commit_selection(state.support_cards, index, {
		"selected_hero_ids": state.selected_hero_ids
	})
	var chosen: Dictionary = state.support_cards[index]
	var hdef := _find_hero_def(String(chosen.get("hero_id", "")))
	if not hdef.is_empty():
		var h := TDBattle.create_hero(hdef, 1)
		h["_def"] = hdef
		h["id"] = "h_%d_%d" % [state.wave, state.heroes.size()]
		h["items"] = [chosen.get("item", {})]
		var spot := _pick_placement()
		if spot != Vector2i(-1, -1):
			h["cell"] = spot
			state.grid.set_cell(spot, TDGrid.Cell.BLOCKED)
		state.heroes.append(h)
		_spawn_hero_node(h)
	_begin_prepare()


func _on_victory() -> void:
	state.advance_phase(TDRunState.Phase.VICTORY)
	print("[Victory] 通关! 波次=%d 剩余HP=%d 金币=%d" % [state.wave, state.base_hp, state.gold])


func _on_defeat() -> void:
	state.advance_phase(TDRunState.Phase.DEFEAT)
	print("[Defeat] 失败于第 %d 波, 剩余HP=%d" % [state.wave, state.base_hp])


# ---------------- 查询辅助 ----------------

func _nearest_hero_in_range(enemy: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1e9
	var rng: float = float(enemy.get("attack_range", 1))
	for h in state.heroes:
		if not bool(h.get("alive", false)):
			continue
		var d := float(abs(int(enemy["cell"].x) - int(h["cell"].x)) + abs(int(enemy["cell"].y) - int(h["cell"].y)))
		if d <= rng and d < best_d:
			best_d = d
			best = h
	return best


func _nearest_enemy_in_range(hero: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1e9
	var rng: float = float(hero.get("stats", {}).get("attack_range", 2))
	for e in state.enemies:
		if not bool(e.get("alive", false)):
			continue
		var d := float(abs(int(hero["cell"].x) - int(e["cell"].x)) + abs(int(hero["cell"].y) - int(e["cell"].y)))
		if d <= rng and d < best_d:
			best_d = d
			best = e
	return best


func _find_hero_def(id: String) -> Dictionary:
	for h in _heroes_data:
		if String(h.get("id", "")) == id:
			return h
	return {}


func _pick_placement() -> Vector2i:
	# 英雄站位：优先进攻路线格（靠前 = 离基地远 = 敌人来的方向）
	var path_cells := state.grid.tower_cells()
	path_cells.sort_custom(func(a, b):
		return state.grid.flow_dist[state.grid.idx(a.x, a.y)] > state.grid.flow_dist[state.grid.idx(b.x, b.y)])
	for c in path_cells:
		if state.grid.can_place(c, TDGrid.PlaceKind.HERO)["ok"]:
			return c
	# 退而求其次：贴路线的空地
	var zone_cells := state.grid.hero_cells()
	zone_cells.sort_custom(func(a, b): return state.grid.dist_to_path(a) < state.grid.dist_to_path(b))
	for c in zone_cells:
		if state.grid.can_place(c, TDGrid.PlaceKind.HERO)["ok"]:
			return c
	return Vector2i(-1, -1)


func _pick_tower_cell() -> Vector2i:
	# 塔位：路线格，且与已有塔保持距离（覆盖全路线而不是堆一处）
	var cells := state.grid.tower_cells()
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for c in cells:
		if not state.grid.can_place(c, TDGrid.PlaceKind.TOWER)["ok"]:
			continue
		var min_dist := 9999.0
		for t in state.towers:
			var tc: Vector2i = t.get("cell", Vector2i.ZERO)
			min_dist = minf(min_dist, float(abs(tc.x - c.x) + abs(tc.y - c.y)))
		if state.towers.is_empty():
			min_dist = 10.0
		if min_dist > best_score:
			best_score = min_dist
			best = c
	return best


# ---------------- 渲染辅助（占位图形，美术阶段替换） ----------------

func _spawn_enemy_node(e: Dictionary) -> void:
	if not battlefield:
		return
	var n := ColorRect.new()
	n.color = _enemy_color(String(e.get("tag", "")))
	n.size = Vector2(40, 40)
	battlefield.unit_layer.add_child(n)
	e["_node"] = n
	_enemy_nodes.append(e)


func _move_enemy_node(e: Dictionary) -> void:
	if not e.has("_node"):
		return
	var n = e["_node"]
	n.position = battlefield.cell_to_world(e["cell"]) - n.size * 0.5


func _remove_enemy_node(e: Dictionary) -> void:
	if not e.has("_node"):
		return
	var n = e["_node"]
	n.queue_free()
	e.erase("_node")
	_enemy_nodes.erase(e)


func _spawn_hero_node(h: Dictionary) -> void:
	if not battlefield:
		return
	var n := ColorRect.new()
	n.color = Color(0.3, 0.7, 1.0)
	n.size = Vector2(44, 44)
	battlefield.unit_layer.add_child(n)
	n.position = battlefield.cell_to_world(h["cell"]) - n.size * 0.5
	h["_node"] = n
	_hero_nodes[String(h.get("id", ""))] = n


func _spawn_tower_node(tw: Dictionary) -> void:
	if not battlefield:
		return
	var n := ColorRect.new()
	n.color = Color(0.9, 0.8, 0.35)
	n.size = Vector2(38, 38)
	battlefield.unit_layer.add_child(n)
	n.position = battlefield.cell_to_world(tw["cell"]) - n.size * 0.5
	tw["_node"] = n
	_tower_nodes[String(tw.get("id", ""))] = n


func _enemy_color(tag: String) -> Color:
	match tag:
		"magic": return Color(0.6, 0.4, 0.95)
		"elite": return Color(1.0, 0.55, 0.15)
		"boss": return Color(1.0, 0.15, 0.35)
		_: return Color(0.85, 0.35, 0.3)
