extends "res://scripts/challenge_screen.gd"

const Rules = preload("res://scripts/challenge_game.gd")
const NormalRules = preload("res://scripts/normal_game.gd")
const PER_PAGE := 16
const CARD_SIZE := Vector2(90, 128)
const GRID_SIZE := Vector2(574, 914)
const GRID_ORIGIN := Vector2(88, 235)
const CHALLENGE_ROOT := UI_ROOT + "Texture/Challenge/"
@export var save_path := Rules.SAVE_PATH
@export var normal_save_path := NormalRules.SAVE_PATH
var game := Rules.new()
var highest_coin := 1
var page := 0
var cards: Array[Button] = []
var _card_layer: Control
var _page_label: Label
var _page_strip: Control
var _page_cards: Array = []
var _page_tween: Tween
var _indicators: Array[TextureRect] = []
var _unlock_dialog: Control
var _unlock_message: Label
var _unlock_suffix: Label
var _unlock_number: Label
var _unlock_coin: TextureRect
var _locked_level := 0
var _swipe_start := Vector2.ZERO
var _swipe_active := false
var _swipe_touch := false
var _swipe_dragging := false
var _swipe_moved := false
var _swipe_vertical := false
var _swipe_card := -1


func _ready() -> void:
	super._ready()
	game.load_game(save_path)
	var normal := NormalRules.new()
	normal.load_game(normal_save_path)
	highest_coin = normal.highest_level
	# WarUI.open always resets the PageView and indicator, regardless of progress.
	page = 0
	var panel := NinePatchRect.new()
	panel.texture = preload(UI_ROOT + "ui/PanelBG.png")
	panel.position = Vector2(42.5, 101)
	panel.size = Vector2(665, 1178)
	panel.patch_margin_left = Ceramic.PANEL_MARGIN
	panel.patch_margin_top = Ceramic.PANEL_MARGIN
	panel.patch_margin_right = Ceramic.PANEL_MARGIN
	panel.patch_margin_bottom = Ceramic.PANEL_MARGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(panel)
	var heading := label("挑战一下", Vector2(150, 135), Vector2(450, 70), 45)
	DialogStyle.title(heading)
	layout.add_child(heading)
	var close := TextureButton.new()
	close.position = Vector2(640, 130)
	close.size = Vector2(81, 81)
	close.texture_normal = preload(UI_ROOT + "ui/Btn_Quit.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.tooltip_text = tr("返回主页")
	close.pressed.connect(_go_to.bind("res://scenes/main_menu.tscn"))
	layout.add_child(close)
	_card_layer = Control.new()
	_card_layer.name = "Levels"
	_card_layer.position = GRID_ORIGIN
	_card_layer.size = GRID_SIZE
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_card_layer)
	_card_layer.clip_contents = true
	_page_strip = Control.new()
	_page_strip.name = "Pages"
	_page_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.add_child(_page_strip)
	_page_label = label("", Vector2(255, 1216), Vector2(240, 40), 22)
	layout.add_child(_page_label)
	var count := _page_count()
	for index in range(count):
		var indicator := texture(preload(UI_ROOT + "ui/Icon_spot_2.png"), Vector2(358 + (index - (count - 1) / 2.0) * 50, 1174), Vector2(34, 34))
		layout.add_child(indicator)
		_indicators.append(indicator)
	_build_unlock_dialog()
	_refresh_page()


func _page_count() -> int:
	# The published menu includes a single unplayable Wait item after level 100.
	return ceili((Rules.Data.LEVELS.size() + 1) / float(PER_PAGE))


func _refresh_page() -> void:
	if _page_tween:
		_page_tween.kill()
		_page_tween = null
	_swipe_active = false
	for child in _page_strip.get_children():
		child.free()
	_page_cards.clear()
	for index in range(_page_count()):
		var container := Control.new()
		container.position = Vector2(index * GRID_SIZE.x, 0)
		container.size = GRID_SIZE
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page_strip.add_child(container)
		_page_cards.append(_build_page(container, index))
	_page_strip.position.x = -page * GRID_SIZE.x
	_update_pagination()


func _update_pagination() -> void:
	cards.assign(_page_cards[page])
	_page_label.text = tr("challenge.swipe_hint")
	for index in range(_indicators.size()):
		_indicators[index].texture = preload(UI_ROOT + "ui/Icon_spot_1.png") if index == page else preload(UI_ROOT + "ui/Icon_spot_2.png")
		for card: Button in _page_cards[index]:
			card.focus_mode = Control.FOCUS_ALL if index == page else Control.FOCUS_NONE


func _build_page(parent: Control, page_index: int) -> Array[Button]:
	var result: Array[Button] = []
	for offset in range(PER_PAGE):
		var number := page_index * PER_PAGE + offset + 1
		if number > Rules.Data.LEVELS.size() + 1:
			break
		var state := "wait" if number > Rules.Data.LEVELS.size() else game.status(number, highest_coin)
		var card := Button.new()
		card.name = "Level%d" % number
		card.position = Vector2(25 + (offset % 4) * 140, 30 + (offset / 4) * 228)
		card.size = CARD_SIZE
		card.disabled = state == "wait"
		card.mouse_default_cursor_shape = Control.CURSOR_ARROW if card.disabled else Control.CURSOR_POINTING_HAND
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		card.pressed.connect(_open_level.bind(number))
		parent.add_child(card)
		card.add_child(texture(preload(CHALLENGE_ROOT + "LevelBG.png"), Vector2.ZERO, CARD_SIZE))
		match state:
			"locked":
				card.add_child(texture(preload(UI_ROOT + "ui/Icon_Lock.png"), Vector2(23.5, 35.5), Vector2(43, 57)))
			"play":
				card.add_child(texture(preload(CHALLENGE_ROOT + "Unlock.png"), Vector2(20.5, 3.178), Vector2(49, 64)))
				var ready_label := label(tr("challenge.available"), Vector2(-3, 86), Vector2(96, 50.4), 24)
				ready_label.add_theme_color_override("font_color", Color("8b789f"))
				card.add_child(ready_label)
			"doing":
				card.add_child(texture(preload(CHALLENGE_ROOT + "BG_Choose.png"), Vector2(-16, -16), Vector2(122, 160)))
				card.add_child(texture(preload(CHALLENGE_ROOT + "Flag.png"), Vector2(26, 29), Vector2(48, 60)))
			"complete":
				# UIHelper.getChallengeSpf ignores the level-specific icon config.
				card.add_child(texture(preload(CHALLENGE_ROOT + "Partten.png"), Vector2(0, 0.5), Vector2(90, 127)))
			"wait":
				var wait_label := label(tr("challenge.wait"), Vector2(-24, 18.8), Vector2(138, 90.4), 28)
				wait_label.add_theme_color_override("font_color", Color("8b789f"))
				card.add_child(wait_label)
		var title := label(tr("challenge.menu_level") % number, Vector2(-25, 133.723), Vector2(140, 31.5), 25)
		card.add_child(title)
		var description := tr("challenge." + state)
		if state == "locked":
			description = tr("challenge.unlock") % Rules.config(number).unlock
		elif state == "complete":
			description = tr("challenge.best_short") % Rules.format_time(game.best_times[str(number)])
		card.tooltip_text = title.text + " · " + description
		result.append(card)
	return result


func _change_page(direction: int) -> void:
	if _modal_open() or _swipe_active or (_page_tween and _page_tween.is_running()):
		return
	_settle_page(clampi(page + direction, 0, _page_count() - 1))


func _settle_page(target: int) -> void:
	if _page_tween:
		_page_tween.kill()
	if target != page:
		_sound("click")
	page = target
	_update_pagination()
	_page_tween = create_tween()
	_page_tween.tween_property(_page_strip, "position:x", -page * GRID_SIZE.x, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_tween.tween_callback(func() -> void: _page_tween = null)


func _modal_open() -> bool:
	return settings_dialog.visible or _unlock_dialog.visible or _leaving


func _open_level(number: int) -> void:
	if _modal_open() or _swipe_active or (_page_tween and _page_tween.is_running()) or Rules.config(number).is_empty():
		return
	if not Rules.is_unlocked(number, highest_coin):
		_sound("click")
		_locked_level = number
		_refresh_unlock_dialog()
		_unlock_dialog.show()
		_unlock_dialog.get_node("Panel/Dismiss").grab_focus()
		return
	Rules.requested_level = number
	_go_to("res://scenes/challenge.tscn")


func _build_unlock_dialog() -> void:
	_unlock_dialog = Control.new()
	_unlock_dialog.name = "UnlockDialog"
	_unlock_dialog.size = Vector2(750, 1334)
	_unlock_dialog.z_index = 25
	_unlock_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	layout.add_child(_unlock_dialog)
	var shade := preload("res://scripts/modal_shade.gd").new()
	_unlock_dialog.add_child(shade)
	var panel := DialogStyle.panel(Vector2(586, 770))
	panel.name = "Panel"
	panel.position = Vector2(82, 282)
	_unlock_dialog.add_child(panel)
	var heading := label("challenge.unlock_title", Vector2(56, 26), Vector2(474, 70), 45)
	DialogStyle.title(heading)
	panel.add_child(heading)
	var close := DialogStyle.close_button(_dismiss_unlock)
	close.name = "Close"
	close.position = Vector2(530, 28)
	panel.add_child(close)
	var row := HBoxContainer.new()
	row.position = Vector2(30, 222)
	row.size = Vector2(526, 100)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_unlock_message = label("challenge.unlock_prefix", Vector2.ZERO, Vector2.ZERO, 40)
	_unlock_message.add_theme_color_override("font_color", DialogStyle.BODY_COLOR)
	row.add_child(_unlock_message)
	_unlock_coin = texture(preload(UI_ROOT + "Texture/skin/big/BigCoin1.png"), Vector2.ZERO, Vector2(52, 55))
	_unlock_coin.custom_minimum_size = Vector2(52, 55)
	_unlock_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_unlock_coin)
	_unlock_number = label("", Vector2.ZERO, Vector2(52, 55), 20)
	_unlock_number.add_theme_font_override("font", Ceramic.FONT)
	_unlock_number.add_theme_color_override("font_color", Ceramic.INK)
	_unlock_coin.add_child(_unlock_number)
	_unlock_suffix = label("challenge.unlock_suffix", Vector2.ZERO, Vector2.ZERO, 40)
	_unlock_suffix.add_theme_color_override("font_color", DialogStyle.BODY_COLOR)
	row.add_child(_unlock_suffix)
	var dismiss := button("challenge.unlock_dismiss", Vector2(133, 420), Vector2(320, 132), _dismiss_unlock)
	dismiss.name = "Dismiss"
	DialogStyle.apply_button(dismiss, "yellow", 42)
	panel.add_child(dismiss)
	var merge := button("challenge.unlock_action", Vector2(133, 588), Vector2(320, 132), _go_to.bind("res://scenes/game.tscn"))
	merge.name = "Merge"
	panel.add_child(merge)
	var controls: Array[Control] = [dismiss, merge, close]
	for index in range(controls.size()):
		var control := controls[index]
		var previous := control.get_path_to(controls[posmod(index - 1, controls.size())])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_top = previous
		control.focus_neighbor_bottom = next
	_refresh_unlock_text()
	_unlock_dialog.hide()


func _refresh_unlock_text() -> void:
	var font_size := 40 if _settings.language == "zh" else 30
	_unlock_message.add_theme_font_size_override("font_size", font_size)
	_unlock_suffix.add_theme_font_size_override("font_size", font_size)
	DialogStyle.fit_button_text(_unlock_dialog.get_node("Panel/Dismiss"), 42)
	DialogStyle.fit_button_text(_unlock_dialog.get_node("Panel/Merge"), 40)


func _refresh_unlock_dialog() -> void:
	_refresh_unlock_text()
	if _locked_level <= 0:
		return
	var required: int = Rules.config(_locked_level).unlock
	_unlock_number.text = str(required)
	_unlock_coin.texture = load(UI_ROOT + "Texture/skin/big/BigCoin%d.png" % (posmod(required - 1, 15) + 1))
	_unlock_coin.tooltip_text = tr("challenge.unlock_body") % required


func _dismiss_unlock() -> void:
	_sound("click")
	_unlock_dialog.hide()
	for card in cards:
		if card.name == "Level%d" % _locked_level:
			card.grab_focus()
			break


func _open_settings() -> void:
	if not _leaving and not _unlock_dialog.visible:
		_sound("click")
		settings_dialog.open_settings(_settings.sound_enabled, _settings.vibration_enabled, _settings.vibration_supported)


func _refresh_language() -> void:
	page = 0
	_refresh_page()
	_refresh_unlock_dialog()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_unlock_dialog):
		return
	if _modal_open():
		if _swipe_active:
			_swipe_active = false
			_settle_page(page)
		return
	if event is InputEventKey:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			get_viewport().set_input_as_handled()
			_change_page(-1 if event.is_action_pressed("ui_left") else 1)
		return
	var at := Vector2.ZERO
	var is_touch := event is InputEventScreenTouch or event is InputEventScreenDrag
	if is_touch:
		if event.index != 0:
			if Rect2(GRID_ORIGIN, GRID_SIZE).has_point(layout.get_global_transform_with_canvas().affine_inverse() * event.position):
				get_viewport().set_input_as_handled()
			return
		at = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		at = event.position
	elif event is InputEventMouseMotion:
		at = event.position
	else:
		return
	at = layout.get_global_transform_with_canvas().affine_inverse() * at
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			if not Rect2(GRID_ORIGIN, GRID_SIZE).has_point(at):
				return
			get_viewport().set_input_as_handled()
			if _swipe_active or (_page_tween and _page_tween.is_running()):
				return
			_swipe_start = at
			_swipe_active = true
			_swipe_touch = is_touch
			_swipe_dragging = false
			_swipe_moved = false
			_swipe_vertical = false
			_swipe_card = _card_at(at)
		elif _swipe_active and is_touch == _swipe_touch:
			get_viewport().set_input_as_handled()
			_finish_swipe(at, event is InputEventScreenTouch and event.canceled)
	elif _swipe_active and is_touch == _swipe_touch:
		get_viewport().set_input_as_handled()
		_drag_swipe(at)


func _card_at(at: Vector2) -> int:
	var local := at - GRID_ORIGIN
	for index in range(cards.size()):
		if cards[index].get_rect().has_point(local):
			return index
	return -1


func _drag_swipe(at: Vector2) -> void:
	var travel := at - _swipe_start
	if travel.length() > 14:
		_swipe_moved = true
	if not _swipe_dragging and not _swipe_vertical and _swipe_moved:
		_swipe_dragging = absf(travel.x) > absf(travel.y) * 1.15
		_swipe_vertical = absf(travel.y) > absf(travel.x) * 1.15
	if _swipe_dragging:
		var offset := travel.x
		if (page == 0 and offset > 0) or (page == _page_count() - 1 and offset < 0):
			offset *= 0.28
		_page_strip.position.x = -page * GRID_SIZE.x + offset


func _finish_swipe(at: Vector2, canceled: bool) -> void:
	_drag_swipe(at)
	_swipe_active = false
	var travel := at - _swipe_start
	if _swipe_dragging or _swipe_moved or canceled:
		var target := page
		if not canceled and _swipe_dragging and absf(travel.x) >= 88:
			target = clampi(page + (1 if travel.x < 0 else -1), 0, _page_count() - 1)
		_settle_page(target)
	elif _swipe_card >= 0 and _card_at(at) == _swipe_card:
		var card := cards[_swipe_card]
		if not card.disabled:
			card.grab_focus()
			card.pressed.emit()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and _swipe_active:
		_swipe_active = false
		_settle_page(page)


func _exit_tree() -> void:
	if _page_tween:
		_page_tween.kill()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not settings_dialog.visible:
		get_viewport().set_input_as_handled()
		if _unlock_dialog.visible:
			_dismiss_unlock()
		else:
			_go_to("res://scenes/main_menu.tscn")
