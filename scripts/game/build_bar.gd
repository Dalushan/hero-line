extends Control
## 建造栏：选择要建的塔 / 英雄 / 升级
##
## 规则判定全在 core（TDGrid.can_place），这里只负责按钮与信号。

signal tower_selected(tower_def: Dictionary)
signal upgrade_selected()
signal cancel_selected()

var tower_defs: Array = []
var state: TDRunState

var _buttons: Array[Button] = []
var _labels: Array[Label] = []


func setup(run_state: TDRunState, defs: Array) -> void:
	state = run_state
	tower_defs = defs
	_render()


func _render() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_labels.clear()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# 塔按钮
	for td in tower_defs:
		var cost := int(td.get("cost", 0))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(112, 58)
		btn.text = "%s\n%d 金" % [String(td.get("name", "塔")), cost]
		btn.tooltip_text = String(td.get("desc", ""))
		btn.pressed.connect(func(): tower_selected.emit(td))
		row.add_child(btn)
		_buttons.append(btn)

	# 升级按钮
	var up := Button.new()
	up.custom_minimum_size = Vector2(112, 58)
	up.text = "升级塔\n点击目标"
	up.pressed.connect(func(): upgrade_selected.emit())
	row.add_child(up)
	_buttons.append(up)

	# 取消
	var cancel := Button.new()
	cancel.custom_minimum_size = Vector2(90, 58)
	cancel.text = "取消\nEsc"
	cancel.pressed.connect(func(): cancel_selected.emit())
	row.add_child(cancel)
	_buttons.append(cancel)


func _process(_delta: float) -> void:
	if state == null:
		return
	# 买不起的塔按钮置灰
	for i in range(mini(_buttons.size(), tower_defs.size())):
		var cost := int(tower_defs[i].get("cost", 0))
		_buttons[i].disabled = state.gold < cost
		_buttons[i].modulate = Color(1, 1, 1, 1.0) if state.gold >= cost else Color(0.6, 0.6, 0.6, 1.0)
