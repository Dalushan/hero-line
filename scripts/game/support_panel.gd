extends Control
## 支援二选一面板。每 5 波弹出，两张卡牌（英雄 + 随机装备）。

signal card_chosen(index: int)

var cards: Array = []
var _buttons: Array[Button] = []


func setup(card_list: Array) -> void:
	cards = card_list
	_render()


func _render() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 320)
	panel.position = Vector2(-380, -160)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "支援到达 —— 选择一名英雄"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	vbox.add_child(row)

	for i in range(cards.size()):
		row.add_child(_make_card(i))


func _make_card(index: int) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(340, 210)
	btn.text = ""
	_buttons.append(btn)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var card: Dictionary = cards[index]
	var name_label := Label.new()
	name_label.text = String(card.get("hero_name", "未知英雄"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(name_label)

	var rarity := String(card.get("hero_rarity", "common"))
	var rarity_text := {"common": "普通", "rare": "稀有", "legendary": "传说"}.get(rarity, rarity)
	var rarity_label := Label.new()
	rarity_label.text = "稀有度: " + rarity_text
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rarity_label)

	var item: Dictionary = card.get("item", {})
	var item_label := Label.new()
	if item.is_empty():
		item_label.text = "无装备"
	else:
		item_label.text = "装备: %s\n%s" % [String(item.get("name", "")), String(item.get("desc", ""))]
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(item_label)

	btn.pressed.connect(func(): card_chosen.emit(index))
	return btn
