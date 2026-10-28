extends Control
## 局内商店面板。
##
## 每波刷新 3 件 buff 候选，价格随波次递增。玩家选择应用到一名英雄身上。
## 规则判定在 core（TDBalance.apply_shop_buff），这里只做 UI 与信号。

signal item_bought(item_index: int, hero_id: String)
signal closed()

var state: TDRunState
var offers: Array = []
var _buttons: Array[Button] = []
var _hero_row: HBoxContainer
var _selected_hero_index := 0


func setup(run_state: TDRunState, offer_list: Array) -> void:
	state = run_state
	offers = offer_list
	_render()


func _render() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()

	# 半透明遮罩（覆盖全屏）
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# ★ 用 CenterContainer 居中，不要手算 position
	#   Control 在 CanvasLayer 下设 PRESET_CENTER 再赋 position，锚点换算会导致面板跑到屏幕外
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 420)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# 标题 + 金钱
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "商店"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var gold_label := Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "金币: %d" % state.gold
	header.add_child(gold_label)

	# 提示
	var hint := Label.new()
	hint.text = "选择要强化的英雄 → 选择商品"
	hint.modulate = Color(0.8, 0.85, 0.95)
	vbox.add_child(hint)

	# 英雄选择行
	var hero_title := Label.new()
	hero_title.text = "英雄"
	vbox.add_child(hero_title)

	_hero_row = HBoxContainer.new()
	_hero_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_hero_row)
	_render_hero_row()

	# 商品行
	var item_title := Label.new()
	item_title.text = "商品"
	vbox.add_child(item_title)

	var item_row := HBoxContainer.new()
	item_row.alignment = BoxContainer.ALIGNMENT_CENTER
	item_row.add_theme_constant_override("separation", 16)
	vbox.add_child(item_row)

	for i in range(offers.size()):
		item_row.add_child(_make_item_card(i))

	# 关闭按钮
	var close := Button.new()
	close.text = "关闭 (Esc)"
	close.custom_minimum_size = Vector2(160, 40)
	close.pressed.connect(func(): closed.emit())
	var close_center := CenterContainer.new()
	close_center.add_child(close)
	vbox.add_child(close_center)


func _render_hero_row() -> void:
	for c in _hero_row.get_children():
		c.queue_free()
	for i in range(state.heroes.size()):
		var h: Dictionary = state.heroes[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 44)
		btn.text = "%s Lv%d" % [String(h.get("name", "")), int(h.get("level", 1))]
		btn.pressed.connect(func(): _select_hero(i))
		_hero_row.add_child(btn)
	_refresh_hero_selection()


func _select_hero(index: int) -> void:
	_selected_hero_index = index
	_refresh_hero_selection()


func _refresh_hero_selection() -> void:
	var i := 0
	for c in _hero_row.get_children():
		var btn := c as Button
		if btn == null:
			continue
		btn.modulate = Color(1, 1, 1) if i == _selected_hero_index else Color(0.7, 0.7, 0.7)
		i += 1


func _make_item_card(index: int) -> Control:
	var item: Dictionary = offers[index]
	var cost := int(item.get("cost", 0))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 190)
	btn.text = ""
	_buttons.append(btn)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var name_label := Label.new()
	name_label.text = String(item.get("name", "商品"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(name_label)

	var desc := Label.new()
	desc.text = _item_desc(item)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var price := Label.new()
	price.text = "%d 金" % cost
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 18)
	box.add_child(price)

	btn.pressed.connect(func(): _buy(index))
	return btn


func _item_desc(item: Dictionary) -> String:
	var value := String(item.get("value", ""))
	var amount := float(item.get("amount", 0.0))
	match value:
		"atk":
			return "攻击力 +%d" % int(amount)
		"hp":
			return "最大生命 +%d" % int(amount)
		"armor":
			return "护甲 +%d" % int(amount)
		"atk_interval":
			return "攻击间隔 -%.2f 秒" % absf(amount)
		"crit":
			return "暴击率 +%d%%" % int(amount * 100.0)
		"gold_bonus":
			return "金币获取 +%d%%" % int(amount * 100.0)
		"revive_discount":
			return "复活费用 -%d%%" % int(amount * 100.0)
		"tower_dmg":
			return "防御塔伤害 +%d%%" % int(amount * 100.0)
		_:
			return "效果未知"


func _buy(index: int) -> void:
	if index < 0 or index >= offers.size():
		return
	if _selected_hero_index < 0 or _selected_hero_index >= state.heroes.size():
		return
	var h: Dictionary = state.heroes[_selected_hero_index]
	var item: Dictionary = offers[index]
	var cost := int(item.get("cost", 0))
	if state.gold < cost:
		return
	# 核心规则走 core
	if not TDBalance.apply_shop_buff(h, item):
		return
	state.gold -= cost
	state.gold_spent += cost
	item_bought.emit(index, String(h.get("id", "")))
	# 买完移除该商品
	offers.remove_at(index)
	_render()


func _process(_delta: float) -> void:
	if state == null:
		return
	var gold_label := find_child("GoldLabel", true, false) as Label
	if gold_label:
		gold_label.text = "金币: %d" % state.gold
	for i in range(mini(_buttons.size(), offers.size())):
		var cost := int(offers[i].get("cost", 0))
		_buttons[i].disabled = state.gold < cost
		_buttons[i].modulate = Color(1, 1, 1, 1.0) if state.gold >= cost else Color(0.6, 0.6, 0.6, 1.0)
