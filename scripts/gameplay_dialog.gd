extends Control
## 普通玩法提示、失败救援和阶段祝贺共用的模态弹窗。

signal action_requested(action: String)

var _title: Label
var _body: Label
var _coin: TextureRect
var _number: Label
var _actions: VBoxContainer
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.59)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var panel := NinePatchRect.new()
	panel.texture = preload("res://assets/rea_original/sprites/ui/PanelBG.png")
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_top = -350
	panel.offset_right = 300
	panel.offset_bottom = 350
	panel.patch_margin_left = 148
	panel.patch_margin_top = 119
	panel.patch_margin_right = 143
	panel.patch_margin_bottom = 119
	add_child(panel)
	_title = _label(Vector2(30, 28), Vector2(540, 70), 42)
	panel.add_child(_title)
	_coin = TextureRect.new()
	_coin.position = Vector2(240, 132)
	_coin.size = Vector2(120, 126)
	_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_coin)
	_number = _label(Vector2.ZERO, Vector2(120, 126), 42)
	_number.add_theme_color_override("font_color", Color.WHITE)
	_number.add_theme_font_override("font", preload("res://assets/rea_original/fonts/number01/number01.fnt"))
	_coin.add_child(_number)
	_body = _label(Vector2(45, 275), Vector2(510, 146), 27)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_body)
	_actions = VBoxContainer.new()
	_actions.position = Vector2(60, 445)
	_actions.size = Vector2(480, 200)
	_actions.add_theme_constant_override("separation", 18)
	panel.add_child(_actions)
	hide()


func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("514a71"))
	return label


func open(title: String, body: String, actions: Array, coin_level: int = 0) -> void:
	_title.text = title
	_body.text = body
	_coin.visible = coin_level > 0
	if coin_level > 0:
		_coin.texture = load("res://assets/rea_original/sprites/Texture/skin/big/BigCoin%d.png" % (posmod(coin_level - 1, 15) + 1))
		_number.text = str(coin_level)
	for child in _actions.get_children():
		child.free()
	for action: Dictionary in actions:
		var button := Button.new()
		button.text = action.label
		button.custom_minimum_size = Vector2(480, 86)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 29)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("32c6b4") if action.get("primary", false) else Color("8c80bc")
			if state == "hover":
				style.bg_color = style.bg_color.lightened(0.1)
			elif state == "pressed":
				style.bg_color = style.bg_color.darkened(0.1)
			style.set_corner_radius_all(22)
			if state == "focus":
				style.border_color = Color("ffe599")
				style.set_border_width_all(3)
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(func() -> void: action_requested.emit(action.id))
		_actions.add_child(button)
	var buttons := _actions.get_children()
	for index in range(buttons.size()):
		var button: Button = buttons[index]
		var previous := button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		var next := button.get_path_to(buttons[(index + 1) % buttons.size()])
		button.focus_previous = previous
		button.focus_next = next
		button.focus_neighbor_top = previous
		button.focus_neighbor_bottom = next
	show()
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_actions.get_child(0).grab_focus()


func _exit_tree() -> void:
	if _tween:
		_tween.kill()
