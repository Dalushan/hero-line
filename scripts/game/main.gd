extends Node
## 主控制器：驱动 core 层的状态机，把状态推给渲染层。
## 关键：所有规则判定在 core，这里只做"调度 + 转发事件"。

const HERO_DEF_PATH := "res://data/hero_def.json"
const ITEM_DEF_PATH := "res://data/item_def.json"
const ENEMY_DEF_PATH := "res://data/enemy_def.json"

var state: TDRunState
var battlefield: Node2D
var support_panel: Control

var _heroes_data: Array = []
var _items_data: Array = []
var _enemies_data: Array = []
var _enemy_def_map: Dictionary = {}

var _wave_timer := 0.0
var _spawn_queue: Array = []
var _spawn_idx := 0
var _time := 0.0
var _enemy_nodes: Array = []
var _hero_nodes: Dictionary = {}


func _ready() -> void:
	_load_data()
	battlefield = get_node_or_null("Battlefield")
	support_panel = get_node_or_null("SupportPanel")
	if battlefield:
		battlefield.connect("tree_exited", Callable())
	_start_new_run()


func _load_data() -> void:
	_heroes_data = _load_json_array(HERO_DEF_PATH, "heroes")
	_items_data = _load_json_array(ITEM_DEF_PATH, "items")
	var enemies := _load_json_array(ENEMY_DEF_PATH, "enemies")
	_enemies_data = enemies
	for e in enemies:
		_enemy_def_map[String(e.get("id", ""))] = e


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
	if battlefield and battlefield.has_method("setup"):
		battlefield.setup(state)
	_begin_prepare()


func _begin_prepare() -> void:
	state.advance_phase(TDRunState.Phase.PREPARING)
	_wave_timer = TDBalance.wave_interval()


func _begin_wave() -> void:
	state.wave += 1
	state.advance_phase(TDRunState.Phase.RUNNING)
	state.wave_groups = TDWaveManager.build_wave(state.wave, state.rng)
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

	# 敌人推进
	for e in state.enemies:
		if not bool(e.get("alive", false)):
			continue
		var target := _nearest_hero_in_range(e)
		if not target.is_empty():
			var cd: float = float(e.get("atk_interval", 1.5))
			if _time >= float(e.get("_next_atk", 0.0)):
				TDBattle.enemy_attack_hero(e, target)
				e["_next_atk"] = _time + cd
			continue
		var step := state.grid.next_step(e["cell"])
		if step == Vector2i.ZERO:
			state.damage_base(int(e.get("damage_to_base", 10)))
			e["alive"] = false
			_remove_enemy_node(e)
			if state.is_game_over():
				_on_defeat()
				return
			continue
		e["cell"] = e["cell"] + step
		_move_enemy_node(e)

	# 英雄攻击
	for h in state.heroes:
		if not bool(h.get("alive", false)):
			continue
		var cd: float = float(h.get("stats", {}).get("atk_interval", 1.0))
		if _time < float(h.get("_next_atk", 0.0)):
			continue
		var tgt := _nearest_enemy_in_range(h)
		if tgt.is_empty():
			h["_next_atk"] = _time + 0.1
			continue
		TDBattle.hero_attack_enemy(h, tgt, _time)
		h["_next_atk"] = _time + cd

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
	var cells := state.grid.buildable_cells()
	if cells.is_empty():
		return Vector2i(-1, -1)
	cells.sort_custom(func(a, b): return state.grid.dist_to_path(a) < state.grid.dist_to_path(b))
	for c in cells:
		if state.grid.can_place(c)["ok"]:
			return c
	return Vector2i(-1, -1)


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
	n.position = battlefield._cell_to_world(e["cell"]) - n.size * 0.5


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
	n.position = battlefield._cell_to_world(h["cell"]) - n.size * 0.5
	h["_node"] = n
	_hero_nodes[String(h.get("id", ""))] = n


func _enemy_color(tag: String) -> Color:
	match tag:
		"magic": return Color(0.6, 0.4, 0.95)
		"elite": return Color(1.0, 0.55, 0.15)
		"boss": return Color(1.0, 0.15, 0.35)
		_: return Color(0.85, 0.35, 0.3)
