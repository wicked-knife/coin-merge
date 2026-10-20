extends "res://scripts/challenge_screen.gd"

signal interstitial_requested(placement: String)

const Rules = preload("res://scripts/challenge_game.gd")
const NormalRules = preload("res://scripts/normal_game.gd")
const SlotView = preload("res://scripts/challenge_slot.gd")
const DialogView = preload("res://scripts/gameplay_dialog.gd")
const FX = preload("res://scripts/normal_effects.gd")
const Motion = preload("res://scripts/normal_motion.gd")
const Platform = preload("res://scripts/challenge_platform.gd")
const SLOT_STEP := Vector2(155, 260)
const BOARD_AREA := Vector2(680, 1084)

@export var save_path := Rules.SAVE_PATH
@export var normal_save_path := NormalRules.SAVE_PATH
var game := Rules.new()
var slots: Array = []
var highest_coin := 1
var _selected := -1
var _busy := false
var _record_mode := false
var _display_level := 1
var _fit := 1.0
var _board_size := Vector2.ZERO
var _autosave := 0.0
var _timer_label: Label
var _progress_label: Label
var _title: Label
var _hint: Label
var _surface: Control
var _board: Control
var _settings_button: TextureButton
var _dialog
var _action_tween: Tween
var _intro_tween: Tween
var _browse_button: Button
var _share_buttons: Array[Button] = []
var _time_running := false
var _can_next := false


func _ready() -> void:
	super._ready()
	game.load_game(save_path)
	var normal := NormalRules.new()
	normal.load_game(normal_save_path)
	highest_coin = normal.highest_level
	_display_level = Rules.requested_level
	if not Rules.is_unlocked(_display_level, highest_coin):
		_display_level = 1
	_record_mode = game.best_times.has(str(_display_level)) and (game.level != _display_level or game.cells.is_empty())
	var resumed := not _record_mode and game.level == _display_level and not game.cells.is_empty() and not game.tutorial
	if not _record_mode and not resumed:
		game.start(_display_level)
	_build_interface()
	_build_board()
	if _record_mode:
		_timer_label.text = Rules.format_time(game.best_times[str(_display_level)])
	elif resumed:
		_time_running = true
		_save()
		call_deferred("_check_win")
	elif game.tutorial:
		_save()
	else:
		_busy = true
		_prepare_show()
		_refresh_actions()
		_save()
		call_deferred("_resume")


func _build_interface() -> void:
	# WarGameUI uses the same pale Bg_Mask sprite as its full-screen background.
	layout.add_child(texture(preload(UI_ROOT + "Texture/skin/Bg_Mask.png"), Vector2.ZERO, layout.size))
	_settings_button = settings_button(_open_settings)
	_settings_button.position = Vector2(24.5, 43.5)
	_settings_button.size = Vector2(91, 101)
	_settings_button.z_index = 16
	layout.add_child(texture(preload(UI_ROOT + "ui/CoinBg.png"), Vector2(235, 58.5), Vector2(280, 71)))
	_title = label("", Vector2(254, 64), Vector2(125, 56), 34)
	_timer_label = label("00:00", Vector2(379, 64), Vector2(121, 56), 34)
	_timer_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_timer_label.text_direction = Control.TEXT_DIRECTION_LTR
	_title.add_theme_color_override("font_color", Ceramic.INK)
	_timer_label.add_theme_color_override("font_color", Ceramic.INK)
	layout.add_child(_title)
	layout.add_child(_timer_label)
	layout.add_child(texture(preload(UI_ROOT + "ui/ProcessBG.png"), Vector2(600, 1246), Vector2(124, 64)))
	_progress_label = label("", Vector2(600, 1246), Vector2(124, 64), 25)
	layout.add_child(_progress_label)
	_surface = Control.new()
	_surface.name = "Layers"
	_surface.position = Vector2(35, 150)
	_surface.size = BOARD_AREA
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_surface)
	_board = _new_board()
	_hint = label("", Vector2(50, 887), Vector2(650, 160), 26)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(_hint)
	_browse_button = Button.new()
	_browse_button.name = "TapToRetry"
	_browse_button.size = layout.size
	_browse_button.z_index = 15
	for state in ["normal", "hover", "pressed", "focus"]:
		_browse_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_browse_button.pressed.connect(_open_record)
	var tap_label := label("challenge.tap_retry", Vector2(150, 1240), Vector2(450, 80), 25)
	_browse_button.add_child(tap_label)
	layout.add_child(_browse_button)
	_browse_button.visible = _record_mode
	# The full-screen record tap area must sit before the gear in GUI hit testing.
	layout.move_child(_settings_button, layout.get_child_count() - 1)
	_dialog = DialogView.new()
	_dialog.name = "ChallengeDialog"
	layout.add_child(_dialog)
	_dialog.action_requested.connect(_on_dialog_action)
	settings_dialog.retry_requested.connect(_retry)
	settings_dialog.home_requested.connect(_home)
	settings_dialog.closed.connect(_refresh_actions)


func _new_board() -> Control:
	var board := Control.new()
	board.name = "Board"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(board)
	return board


func _build_board() -> void:
	if _intro_tween:
		_intro_tween.kill()
	for child in _board.get_children():
		child.free()
	slots.clear()
	_selected = -1
	var board_cells: Array = Rules.completed_cells(_display_level) if _record_mode else game.cells
	var dimensions := Vector2i(Rules.config(_display_level).columns, Rules.config(_display_level).rows) if _record_mode else game.dimensions()
	_board_size = Vector2(110 * dimensions.x + 45 * (dimensions.x - 1), 200 * dimensions.y + 60 * (dimensions.y - 1) + 50)
	_board.size = _board_size
	for index in range(board_cells.size()):
		var slot := SlotView.new()
		slot.name = "Slot%d" % index
		slot.index = index
		slot.position = Vector2((index % dimensions.x) * SLOT_STEP.x, 30 + (index / dimensions.x) * SLOT_STEP.y)
		slot.pressed.connect(_on_slot_pressed)
		_board.add_child(slot)
		slot.render(board_cells[index])
		if _record_mode:
			slot.tick.hide()
		slots.append(slot)
	_fit = 0.8 if game.tutorial and not _record_mode else minf(BOARD_AREA.x / _board_size.x, BOARD_AREA.y / _board_size.y)
	_board.scale = Vector2.ONE * _fit
	_board.position = (BOARD_AREA - _board_size * _fit) / 2.0
	_refresh_language()
	_refresh_actions()


func _prepare_show() -> void:
	for slot in slots:
		slot.prepare_show()


func _resume() -> void:
	_busy = true
	_time_running = false
	_refresh_actions()
	_intro_tween = create_tween().set_parallel(true)
	var columns: int = game.dimensions().x
	for index in range(slots.size()):
		slots[index].play_show(_intro_tween, ((index % columns) + (index / columns)) * 0.05)
	_sound("giveCoin2")
	if not await Motion.finish_or_exit(_intro_tween, self):
		return
	_busy = false
	_time_running = true
	_refresh_actions()
	_check_win()


func _process(delta: float) -> void:
	if _timer_label == null or _record_mode or _leaving:
		return
	# Entrances/transitions are excluded; moves and settings retain the clock.
	if _time_running:
		game.advance_time(delta)
	_timer_label.text = Rules.format_time(game.elapsed)
	_autosave += delta
	if _autosave >= 5.0:
		_autosave = 0.0
		_save()


func _can_interact() -> bool:
	return not _busy and not _leaving and not _record_mode and not game.finished and not settings_dialog.visible and not _dialog.visible


func _refresh_actions() -> void:
	var active: bool = not _busy and not _leaving and not settings_dialog.visible and not _dialog.visible
	_settings_button.disabled = not active
	_browse_button.disabled = not active
	_browse_button.visible = _record_mode and not _dialog.visible


func _on_slot_pressed(index: int) -> void:
	if not _can_interact():
		return
	if _selected == index:
		_cancel_selection()
		_vibrate()
		_sound("chooseCoin")
		return
	if _selected < 0:
		var count := game.selected_count(index)
		if count > 0:
			_selected = index
			slots[index].select_coins(count)
			_sound("chooseCoin")
			_vibrate()
		return
	_move_selected(index)


func _cancel_selection() -> void:
	if _selected >= 0:
		slots[_selected].select_coins(0)
	_selected = -1


func _move_selected(target: int) -> void:
	var source := _selected
	var old_ticks := [game.is_tick(source), game.is_tick(target)]
	var result := game.move(source, target)
	_selected = -1
	_busy = true
	_refresh_actions()
	if result.is_empty():
		_vibrate()
		_sound("warn")
		var shake: Tween = slots[source].shake_selected()
		if not await Motion.finish_or_exit(shake, self):
			return
		_busy = false
		_refresh_actions()
		return
	_save()
	_vibrate()
	_action_tween = create_tween().set_parallel(true)
	var flying: Array = slots[source].take_tail(result.count)
	var other: Array = []
	if result.kind == "swap":
		other = slots[target].take_tail(result.other_count)
		slots[source].render(game.cells[source])
		slots[source].hide_tail(other.size())
	else:
		slots[source].select_coins(0)
		for offset: int in result.revealed:
			slots[source].coin_views[offset].reveal(_action_tween, game.cells[source].coins[offset])
	slots[target].render(game.cells[target])
	slots[target].hide_tail(flying.size())
	_animate_flight(flying, target)
	_animate_flight(other, source)
	if not await Motion.finish_or_exit(_action_tween, self):
		return
	for view in flying + other:
		view.queue_free()
	for index: int in [source, target]:
		slots[index].render(game.cells[index])
	for offset in range(2):
		var index: int = [source, target][offset]
		if not old_ticks[offset] and game.is_tick(index):
			_sound("tz_full")
			slots[index].show_target_light()
	_busy = false
	_refresh_language()
	_refresh_actions()
	_save()
	_check_win()


func _animate_flight(views: Array, target: int) -> void:
	var start: int = game.cells[target].coins.size() - views.size()
	for offset in range(views.size()):
		var view: TextureRect = views[offset]
		# Match the original target coinParent coordinate space, independent of fit.
		view.reparent(slots[target].coin_parent)
		view.scale = Vector2.ONE
		var destination := SlotView.coin_position(start + offset)
		var duration := clampf(view.position.distance_to(destination) / 1500.0, 0.05, 0.25)
		var delay := 0.035 * (views.size() - offset - 1)
		_action_tween.tween_property(view, "position", destination, duration).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_action_tween.tween_callback(_sound.bind("placeCoin")).set_delay(delay + duration)
	if not views.is_empty():
		slots[target].z_index = 10


func _check_win() -> void:
	if _record_mode or game.finished or not game.is_won() or _leaving:
		return
	var result := game.finish()
	_save()
	if result.get("tutorial", false):
		_transition_board()
		return
	_busy = true
	_time_running = false
	_refresh_actions()
	_sound("get_coin")
	_action_tween = create_tween().set_parallel(true)
	var columns: int = game.dimensions().x
	for index in range(slots.size()):
		slots[index].play_success(_action_tween, ((index % columns) + (index / columns)) * 0.05)
	if not await Motion.finish_or_exit(_action_tween, self):
		return
	FX.fireworks(layout)
	_action_tween = create_tween()
	_action_tween.tween_interval(0.8)
	if not await Motion.finish_or_exit(_action_tween, self):
		return
	_busy = false
	_open_success(result)


func _open_success(result: Dictionary) -> void:
	var note := ""
	if result.first:
		note = "challenge.first_reward"
	elif result.record:
		note = "challenge.new_record"
	_can_next = result.first and Rules.is_unlocked(game.level + 1, highest_coin)
	var actions: Array = [{"id": "next", "label": "challenge.next", "tone": "yellow"}] if _can_next else [{"id": "levels", "label": "challenge.back", "tone": "yellow"}]
	_dialog.open("challenge.complete", "", actions, 0, {
		"close_action": "levels",
		"result": {"time": result.time, "best": result.best},
		"note": note,
		"reward": result.first,
		"secondary_actions": [
			{"id": "share", "label": "challenge.share"},
			{"id": "share", "label": "challenge.video_share"},
		],
	})
	_share_buttons = _dialog.secondary_buttons.duplicate()
	_refresh_actions()
	interstitial_requested.emit("war-level-complete")
	Platform.request_interstitial("war-level-complete")


func _open_record() -> void:
	if not _record_mode or _busy or _leaving or settings_dialog.visible:
		return
	_sound("click")
	_share_buttons.clear()
	_dialog.open("challenge.record", "", [
		{"id": "retry", "label": "challenge.replay", "tone": "yellow"},
		{"id": "close_record", "label": "challenge.dismiss"},
	], 0, {"close_action": "close_record", "record_seconds": game.best_times[str(_display_level)]})
	_refresh_actions()


func _on_dialog_action(action: String) -> void:
	if _leaving or _busy:
		return
	_sound("click")
	match action:
		"levels", "share":
			_return_to_levels()
		"close_record":
			_dialog.hide()
			_refresh_actions()
		"retry":
			_retry()
		"next":
			if _can_next and Rules.is_unlocked(game.level + 1, highest_coin):
				_display_level = game.level + 1
				_start_level()


func _retry() -> void:
	if _busy or _leaving or (game.tutorial and not _record_mode):
		return
	_start_level()


func _start_level() -> void:
	_record_mode = false
	_time_running = false
	game.start(_display_level, false)
	_dialog.hide()
	settings_dialog.hide()
	_save()
	_transition_board()


func _transition_board() -> void:
	_busy = true
	_time_running = false
	_cancel_selection()
	var previous := _board
	_board = _new_board()
	_build_board()
	_prepare_show()
	var destination := _board.position
	_board.position.x += 750
	_progress_label.hide()
	_hint.hide()
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.tween_property(_board, "position", destination, 0.8)
	_intro_tween.tween_property(previous, "position:x", previous.position.x - 750, 0.8)
	if not await Motion.finish_or_exit(_intro_tween, self):
		return
	previous.queue_free()
	_refresh_language()
	_progress_label.show()
	_resume()


func _open_settings() -> void:
	if _busy or _leaving or _dialog.visible:
		return
	_sound("click")
	_save()
	settings_dialog.open_settings(_settings.sound_enabled, _settings.vibration_enabled, _settings.vibration_supported, true)
	settings_dialog.retry_button.disabled = false
	_refresh_actions()


func _return_to_levels() -> void:
	_save()
	_go_to("res://scenes/challenge_menu.tscn")


func _home() -> void:
	_save()
	_go_to("res://scenes/main_menu.tscn")


func _refresh_language() -> void:
	_title.text = tr("challenge.hud_level") % _display_level
	DialogStyle.fit_label(_title, 125, 34)
	if _record_mode:
		_timer_label.text = Rules.format_time(game.best_times[str(_display_level)])
	if _record_mode:
		var count := slots.filter(func(slot): return not slot.coin_views.is_empty()).size()
		_progress_label.text = "%d / %d" % [count, count]
	else:
		_progress_label.text = "%d / %d" % [game.completed_count(), game.target_count()]
	_hint.visible = game.tutorial and not _record_mode
	_hint.text = tr("challenge.tutorial_hint").replace("\\n", "\n")
	DialogStyle.refresh_text(_hint)
	DialogStyle.fit_wrapped_label(_hint, Vector2(650, 220), 26)
	if game.tutorial and not _record_mode:
		_timer_label.text = "00:00"


func _vibrate() -> void:
	if _settings.vibration_enabled and _settings.vibration_supported:
		Input.vibrate_handheld(15)


func _save() -> void:
	# Inspecting a completed level must preserve another level's in-progress board.
	if not _record_mode and not game.save_game(save_path):
		push_warning("Unable to save challenge progress.")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _leaving and not _busy and not settings_dialog.visible and not _dialog.visible:
		get_viewport().set_input_as_handled()
		_open_settings()


func _notification(what: int) -> void:
	super._notification(what)
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED]:
		_save()


func _exit_tree() -> void:
	_save()
	for tween in [_action_tween, _intro_tween]:
		if tween:
			tween.kill()
