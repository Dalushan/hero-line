extends Node2D
## 战场交互层：鼠标点击建塔 / 选英雄 / 打开商店
##
## 与 core 的边界：
##   core/  —— 判定"能不能放"（can_place）和"放了什么"（create_tower）
##   game/  —— 决定"玩家点了哪里"和"怎么反馈"

signal cell_clicked(cell: Vector2i, kind: int)
signal cell_hovered(cell: Vector2i, kind: int, ok: bool, reason: String)

const CELL_SIZE := 48
const GRID_ORIGIN := Vector2(120, 60)

enum BuildMode {
	NONE,       ## 只查看
	TOWER,      ## 选塔种，准备建塔
	HERO,       ## 准备放英雄
	UPGRADE,    ## 升级塔
}

@onready var grid_layer: Node2D = $GridLayer
@onready var unit_layer: Node2D = $UnitLayer
@onready var fx_layer: Node2D = $FxLayer
@onready var hud: CanvasLayer = $HUD

var state: TDRunState
var build_mode: int = BuildMode.NONE
var pending_tower_def: Dictionary = {}
var pending_hero_def: Dictionary = {}
var hover_cell := Vector2i(-1, -1)
var hover_ok := false
var hover_reason := ""

var _hover_rect: ColorRect
var _range_circle: Node2D


func setup(run_state: TDRunState) -> void:
	state = run_state
	_redraw_grid()
	_update_hud()


func _ready() -> void:
	_hover_rect = ColorRect.new()
	_hover_rect.color = Color(1, 1, 1, 0.25)
	_hover_rect.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
	_hover_rect.visible = false
	fx_layer.add_child(_hover_rect)


func _process(_delta: float) -> void:
	if state == null:
		return
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseMotion:
		var cell: Vector2i = world_to_cell(get_global_mouse_position())
		if cell != hover_cell:
			hover_cell = cell
			_update_hover()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_cell: Vector2i = world_to_cell(get_global_mouse_position())
		if state.grid.in_bounds(click_cell.x, click_cell.y):
			cell_clicked.emit(click_cell, build_mode)


# ---------------- 建造模式 ----------------

func set_build_tower(tower_def: Dictionary) -> void:
	pending_tower_def = tower_def
	build_mode = BuildMode.TOWER if not tower_def.is_empty() else BuildMode.NONE
	_update_hover()


func set_build_hero(hero_def: Dictionary) -> void:
	pending_hero_def = hero_def
	build_mode = BuildMode.HERO if not hero_def.is_empty() else BuildMode.NONE
	_update_hover()


func set_upgrade_mode() -> void:
	build_mode = BuildMode.UPGRADE
	_update_hover()


func clear_build_mode() -> void:
	build_mode = BuildMode.NONE
	pending_tower_def = {}
	pending_hero_def = {}
	_update_hover()


## 当前模式下的放置校验（复用 core 的 can_place，不重复实现规则）
func validate_cell(cell: Vector2i) -> Dictionary:
	match build_mode:
		BuildMode.TOWER:
			return state.grid.can_place(cell, TDGrid.PlaceKind.TOWER)
		BuildMode.HERO:
			return state.grid.can_place(cell, TDGrid.PlaceKind.HERO)
		BuildMode.UPGRADE:
			# 升级：检查该格是否有塔
			for t in state.towers:
				var tc: Vector2i = t.get("cell", Vector2i.ZERO)
				if tc == cell:
					if int(t.get("level", 1)) >= TDTower.MAX_LEVEL:
						return {"ok": false, "reason": "塔已满级"}
					return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "该格没有防御塔"}
		_:
			return {"ok": false, "reason": ""}


func _update_hover() -> void:
	if build_mode == BuildMode.NONE:
		_hover_rect.visible = false
		hover_ok = false
		hover_reason = ""
		return
	var res := validate_cell(hover_cell)
	hover_ok = bool(res["ok"])
	hover_reason = String(res.get("reason", ""))
	_hover_rect.visible = true
	_hover_rect.position = GRID_ORIGIN + Vector2(hover_cell.x * CELL_SIZE, hover_cell.y * CELL_SIZE)
	_hover_rect.color = Color(0.3, 1.0, 0.4, 0.35) if hover_ok else Color(1.0, 0.3, 0.3, 0.35)
	cell_hovered.emit(hover_cell, build_mode, hover_ok, hover_reason)


# ---------------- 坐标转换 ----------------

func cell_to_world(c: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2(c.x * CELL_SIZE + CELL_SIZE * 0.5, c.y * CELL_SIZE + CELL_SIZE * 0.5)


func world_to_cell(w: Vector2) -> Vector2i:
	var local := (w - GRID_ORIGIN) / CELL_SIZE
	return Vector2i(floori(local.x), floori(local.y))


# ---------------- 渲染 ----------------

func _redraw_grid() -> void:
	for child in grid_layer.get_children():
		child.queue_free()

	var g := state.grid
	for y in range(g.height):
		for x in range(g.width):
			var cell := Vector2i(x, y)
			var rect := Rect2(GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var color := Color(0.22, 0.24, 0.28)
			match g.get_cell(cell):
				TDGrid.Cell.GROUND:
					color = Color(0.85, 0.25, 0.25)
				TDGrid.Cell.PATH:
					color = Color(0.38, 0.32, 0.22)
				TDGrid.Cell.BUILDABLE:
					color = Color(0.20, 0.30, 0.24)
				TDGrid.Cell.BLOCKED:
					color = Color(0.30, 0.30, 0.38)
			var cell_node := ColorRect.new()
			cell_node.color = color
			cell_node.position = rect.position
			cell_node.size = rect.size - Vector2(1, 1)
			grid_layer.add_child(cell_node)

	# 基地标记
	var base_node := ColorRect.new()
	base_node.color = Color(0.9, 0.75, 0.2)
	base_node.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
	base_node.position = cell_to_world(state.grid.base_cell) - base_node.size * 0.5
	grid_layer.add_child(base_node)

	# 出兵口标记
	var spawn_node := ColorRect.new()
	spawn_node.color = Color(0.85, 0.25, 0.25)
	spawn_node.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
	spawn_node.position = cell_to_world(state.grid.spawn_cell) - spawn_node.size * 0.5
	grid_layer.add_child(spawn_node)


func _update_hud() -> void:
	if hud == null:
		return
	var wave_label := hud.get_node_or_null("Margin/VBox/WaveLabel")
	if wave_label:
		wave_label.text = "第 %d / %d 波" % [state.wave, TDBalance.waves_per_stage()]
	var gold_label := hud.get_node_or_null("Margin/VBox/GoldLabel")
	if gold_label:
		gold_label.text = "金币: %d" % state.gold
	var hp_label := hud.get_node_or_null("Margin/VBox/BaseHpLabel")
	if hp_label:
		hp_label.text = "基地 HP: %d / %d" % [state.base_hp, state.base_hp_max]
	var hero_label := hud.get_node_or_null("Margin/VBox/HeroLabel")
	if hero_label:
		var names: Array[String] = []
		for h in state.heroes:
			names.append("%s Lv%d" % [String(h.get("name", "")), int(h.get("level", 1))])
		hero_label.text = "英雄: " + (", ".join(names) if names.size() > 0 else "无")
	var tower_label := hud.get_node_or_null("Margin/VBox/TowerLabel")
	if tower_label:
		tower_label.text = "防御塔: %d" % state.towers.size()
	var hint_label := hud.get_node_or_null("Margin/VBox/HintLabel")
	if hint_label:
		if build_mode == BuildMode.NONE:
			hint_label.text = "提示: 点击塔按钮建塔, 点击英雄按钮部署英雄"
		else:
			hint_label.text = "提示: %s (Esc 取消)%s" % [
				_build_mode_name(),
				"" if hover_ok else "  ⚠ " + hover_reason]
		hint_label.modulate = Color(1, 0.85, 0.4) if not hover_ok else Color(0.8, 1, 0.8)


func _build_mode_name() -> String:
	match build_mode:
		BuildMode.TOWER:
			return "建造: %s" % String(pending_tower_def.get("name", "防御塔"))
		BuildMode.HERO:
			return "部署: %s" % String(pending_hero_def.get("name", "英雄"))
		BuildMode.UPGRADE:
			return "升级防御塔"
		_:
			return ""
