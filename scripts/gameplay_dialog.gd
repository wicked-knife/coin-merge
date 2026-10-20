extends Control
## Shared dialogs for rescue, challenge results and records.

signal action_requested(action: String)

const Style = preload("res://scripts/dialog_style.gd")
var _panel: NinePatchRect
var _title: Label
var _body: Label
var _coin: TextureRect
var _number: Label
var _action_note: Label
var _note_row: HBoxContainer
var _actions: VBoxContainer
var _secondary: HBoxContainer
var secondary_buttons: Array[Button] = []
var _close: TextureButton
var _close_action := ""
var _summary: Panel
var _result_caption: Label
var _result_time: Label
var _result_best: Label
var _reward_icon: TextureRect
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := preload("res://scripts/modal_shade.gd").new()
	add_child(shade)
	_panel = Style.panel(Vector2(586, 770))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -293
	_panel.offset_top = -385
	_panel.offset_right = 293
	_panel.offset_bottom = 385
	add_child(_panel)
	_title = _label(Vector2(56, 26), Vector2(474, 70), 45)
	Style.title(_title)
	_panel.add_child(_title)
	_close = Style.close_button(func() -> void: action_requested.emit(_close_action))
	_close.position = Vector2(530, 28)
	_panel.add_child(_close)
	_coin = TextureRect.new()
	_coin.position = Vector2(237, 140)
	_coin.size = Vector2(112, 118)
	_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_coin)
	_number = _label(Vector2.ZERO, _coin.size, 42)
	_number.add_theme_color_override("font_color", Color.WHITE)
	_number.add_theme_font_override("font", preload("res://assets/rea_original/fonts/number01/number01.fnt"))
	_coin.add_child(_number)
	_body = _label(Vector2(46, 270), Vector2(494, 106), 32)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_body)
	_note_row = HBoxContainer.new()
	_note_row.position = Vector2(46, 382)
	_note_row.size = Vector2(494, 42)
	_note_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_note_row.add_theme_constant_override("separation", 12)
	_note_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_note_row)
	_action_note = _label(Vector2.ZERO, Vector2.ZERO, 28)
	_note_row.add_child(_action_note)
	_actions = VBoxContainer.new()
	_actions.position = Vector2(46, 444)
	_actions.size = Vector2(494, 274)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 18)
	_panel.add_child(_actions)
	_secondary = HBoxContainer.new()
	_secondary.position = Vector2(56, 589)
	_secondary.size = Vector2(474, 106)
	_secondary.add_theme_constant_override("separation", 22)
	_secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_secondary)
	_build_result_summary()
	hide()


func _build_result_summary() -> void:
	_summary = Panel.new()
	_summary.position = Vector2(52, 142)
	_summary.size = Vector2(482, 210)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := StyleBoxFlat.new()
	card.bg_color = Color(1, 1, 1, 0.4)
	card.set_corner_radius_all(24)
	_summary.add_theme_stylebox_override("panel", card)
	_panel.add_child(_summary)
	_result_caption = _label(Vector2(20, 13), Vector2(442, 42), 28)
	_result_caption.text = "challenge.your_time"
	_summary.add_child(_result_caption)
	_result_time = _label(Vector2(12, 56), Vector2(458, 78), 48)
	_result_time.clip_text = true
	_summary.add_child(_result_time)
	_result_best = _label(Vector2(12, 145), Vector2(458, 44), 28)
	_result_best.clip_text = true
	_summary.add_child(_result_best)
	_reward_icon = TextureRect.new()
	_reward_icon.texture = preload("res://assets/rea_original/sprites/ui/Gold_Small.png")
	_reward_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reward_icon.custom_minimum_size = Vector2(40, 40)
	_reward_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reward_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_row.add_child(_reward_icon)
	_note_row.move_child(_reward_icon, 0)


func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var view := Label.new()
	view.position = at
	view.size = dimensions
	view.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_theme_font_size_override("font_size", font_size)
	view.add_theme_color_override("font_color", Style.BODY_COLOR)
	return view


func open(title: String, body: String, actions: Array, coin_level: int = 0, presentation: Dictionary = {}) -> void:
	_title.text = title
	Style.title(_title)
	_body.text = body
	_close_action = presentation.get("close_action", "")
	_close.visible = not _close_action.is_empty()
	var result: Dictionary = presentation.get("result", {})
	var record_time: String = presentation.get("record_time", "")
	_summary.visible = not result.is_empty() or not record_time.is_empty()
	_body.visible = not _summary.visible
	_note_row.position.y = 368 if _summary.visible else 382
	_action_note.text = presentation.get("note", actions[0].get("note", "") if not actions.is_empty() else "")
	_action_note.visible = not _action_note.text.is_empty()
	_reward_icon.visible = presentation.get("reward", false)
	Style.fit_label(_action_note, 442 if _reward_icon.visible else 494, 28)
	if not result.is_empty():
		_result_caption.text = "challenge.your_time"
		_result_time.text = result.time
		_result_best.text = tr("challenge.best") % result.best
	elif not record_time.is_empty():
		_result_caption.text = "challenge.best_label"
		_result_time.text = record_time
		_result_best.text = "challenge.record_hint"
	Style.fit_label(_result_time, 450, 48)
	Style.fit_label(_result_best, 450, 28)
	_coin.visible = coin_level > 0
	if coin_level > 0:
		_coin.texture = load("res://assets/rea_original/sprites/Texture/skin/big/BigCoin%d.png" % (posmod(coin_level - 1, 15) + 1))
		_number.text = str(coin_level)
	_body.position.y = 270 if coin_level > 0 else 154
	_body.size.y = 106 if coin_level > 0 else 210
	for container in [_actions, _secondary]:
		for child in container.get_children():
			child.free()
	secondary_buttons.clear()
	var secondary: Array = presentation.get("secondary_actions", [])
	_secondary.visible = not secondary.is_empty()
	_actions.position.y = 425 if not secondary.is_empty() else 444
	_actions.size.y = 132 if not secondary.is_empty() else 274
	for action: Dictionary in actions:
		var button := _make_button(action, Vector2(320, 128), 40)
		_actions.add_child(button)
		Style.fit_button_text(button)
	for action: Dictionary in secondary:
		var button := _make_button(action, Vector2(226, 106), 32)
		_secondary.add_child(button)
		Style.fit_button_text(button, 32)
		secondary_buttons.append(button)
	var buttons: Array = _actions.get_children() + _secondary.get_children()
	if _close.visible:
		buttons.append(_close)
	for index in range(buttons.size()):
		var button: Control = buttons[index]
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
	if not buttons.is_empty():
		buttons[0].grab_focus()


func _make_button(action: Dictionary, dimensions: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = action.label
	button.custom_minimum_size = dimensions
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Style.apply_button(button, action.get("tone", "rescue" if action.get("primary", false) else "blue"), font_size)
	button.pressed.connect(func() -> void: action_requested.emit(action.id))
	return button


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and not _close_action.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		action_requested.emit(_close_action)


func _exit_tree() -> void:
	if _tween:
		_tween.kill()
