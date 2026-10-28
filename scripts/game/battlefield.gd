extends Node2D
## 战场渲染层：把 core 层的纯数据状态画出来
## 核心逻辑完全不在这里 —— 这个节点只负责"读状态 → 画出来"

const CELL_SIZE := 48
const GRID_ORIGIN := Vector2(120, 60)

@onready var grid_layer: Node2D = $GridLayer
@onready var unit_layer: Node2D = $UnitLayer
@onready var fx_layer: Node2D = $FxLayer
@onready var hud: CanvasLayer = $HUD

var state: TDRunState
var _hp_font: Font


func setup(run_state: TDRunState) -> void:
	state = run_state
	_redraw_grid()
	_update_hud()


func _ready() -> void:
	_hp_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if state == null:
		return
	_update_hud()


func _cell_to_world(c: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2(c.x * CELL_SIZE + CELL_SIZE * 0.5, c.y * CELL_SIZE + CELL_SIZE * 0.5)


func _world_to_cell(w: Vector2) -> Vector2i:
	var local := (w - GRID_ORIGIN) / CELL_SIZE
	return Vector2i(floori(local.x), floori(local.y))


func _redraw_grid() -> void:
	for child in grid_layer.get_children():
		child.queue_free()

	var g := state.grid
	for y in range(g.height):
		for x in range(g.width):
			var cell := Vector2i(x, y)
			var rect := Rect2(GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var c := g.get_cell(cell)
			var color := Color(0.22, 0.24, 0.28)
			match c:
				TDGrid.Cell.GROUND:
					color = Color(0.35, 0.30, 0.22)
				TDGrid.Cell.BUILDABLE:
					color = Color(0.20, 0.26, 0.22)
				TDGrid.Cell.BLOCKED:
					color = Color(0.30, 0.30, 0.36)
			draw_rect(Rect2(), Color(0, 0, 0, 0))
			var cell_node := ColorRect.new()
			cell_node.color = color
			cell_node.position = rect.position
			cell_node.size = rect.size - Vector2(1, 1)
			grid_layer.add_child(cell_node)

	# 基地标记
	var base_pos := _cell_to_world(state.grid.base_cell)
	var base_node := ColorRect.new()
	base_node.color = Color(0.9, 0.75, 0.2)
	base_node.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
	base_node.position = base_pos - base_node.size * 0.5
	grid_layer.add_child(base_node)

	# 出兵口标记
	var spawn_pos := _cell_to_world(state.grid.spawn_cell)
	var spawn_node := ColorRect.new()
	spawn_node.color = Color(0.85, 0.25, 0.25)
	spawn_node.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
	spawn_node.position = spawn_pos - spawn_node.size * 0.5
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
