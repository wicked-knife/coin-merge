extends Control

# 平台接入点。当前原型直接放行奖励，不依赖广告服务。
signal reward_requested(placement: String, completion: Callable)

const SettingsStore = preload("res://scripts/game_settings.gd")
const Rules = preload("res://scripts/normal_game.gd")
const SlotView = preload("res://scripts/coin_slot.gd")
const FX = preload("res://scripts/normal_effects.gd")
const ProgressView = preload("res://scripts/normal_progress.gd")
const TutorialView = preload("res://scripts/normal_tutorial.gd")
const CongratsView = preload("res://scripts/normal_congrats.gd")
const GameplayDialog = preload("res://scripts/gameplay_dialog.gd")
const ROOT := "res://assets/rea_original/"
const SLOT_NAMES := ["Slot31", "Slot32", "Slot33", "Slot34", "Slot21", "Slot22", "Slot23", "Slot24", "Slot11", "Slot12", "Slot13", "Slot14"]
const GUIDE_SLOTS := {0: 0, 1: 2, 4: 0, 5: 1, 6: 2, 7: 1}

@export var bypass_reward_ads := true
@export var save_path := Rules.SAVE_PATH
@onready var settings_button: TextureButton = $Layout/TopBar/SettingsButton
@onready var deal_button: TextureButton = $Layout/BottomBar/DealButton
@onready var settings_dialog = $SettingsDialog
@onready var effects: Control = $Layout/Effects
@onready var hint: Label = $Layout/Hint

var game := Rules.new()
var slots: Array = []
var _settings := SettingsStore.shared()
var _selected := -1
var _busy := false
var _leaving := false
var _auto_pending := false
var _failure_pending := false
var _board_generation := 0
var _button_tween: Tween
var _return_tween: Tween
var _action_tween: Tween
var _auto_tween: Tween
var _failure_tween: Tween
var _toast_tween: Tween
var _decoration_tweens: Array[Tween] = []
var _dialog
var _reward_placement := ""
var _reward_cell := -1
var _toast_generation := 0
var _toast_message := ""
var _sound_cache := {}
var _progress := ProgressView.new()
var _tutorial
var _congrats
var _holding_board := false
var _pending_next_level := false
var _old_board: Control


func _ready() -> void:
	settings_dialog.set_language(_settings.language)
	settings_button.pivot_offset = settings_button.size / 2.0
	settings_button.button_down.connect(_animate_settings_button.bind(true))
	settings_button.button_up.connect(_animate_settings_button.bind(false))
	settings_button.mouse_exited.connect(_animate_settings_button.bind(false))
	settings_dialog.retry_requested.connect(_on_retry_requested)
	deal_button.pivot_offset = deal_button.size / 2.0
	for index in range(SLOT_NAMES.size()):
		var slot = $Layout/Board/Slots.get_node(SLOT_NAMES[index])
		slot.index = index
		slot.pressed.connect(_on_slot_pressed)
		slots.append(slot)
	_dialog = GameplayDialog.new()
	_dialog.name = "GameplayDialog"
	add_child(_dialog)
	move_child(_dialog, settings_dialog.get_index())
	_dialog.action_requested.connect(_on_dialog_action)
	_progress.setup($Layout/TopBar/Progress)
	_tutorial = TutorialView.new()
	_tutorial.name = "Tutorial"
	$Layout.add_child(_tutorial)
	_tutorial.activated.connect(_on_tutorial_activated)
	_congrats = CongratsView.new()
	_congrats.name = "Congrats"
	$Layout.add_child(_congrats)
	_congrats.dismissed.connect(_on_congrats_dismissed)
	_start_decorations()
	game.load_game(save_path)
	# 选中引用不存档，恢复时重播这对点击，已完成的搬运无需回滚。
	if game.guide_step in [1, 5, 7]:
		game.guide_step -= 1
	_render_all()
	_save_board()
	call_deferred("_resume_board")


func _resume_board() -> void:
	_update_tutorial()
	_settle_board()


func _render_all() -> void:
	if _holding_board:
		_refresh_actions()
		return
	for index in range(slots.size()):
		var count := game.selected_count(index) if index == _selected else 0
		slots[index].render(game.cells[index], count, GUIDE_SLOTS.get(game.guide_step, -1) == index, game.can_merge(index))
	_refresh_progress()
	_refresh_actions()


func _refresh_progress() -> void:
	var targets := game.targets()
	var current := game.stage()
	if _holding_board:
		return
	_progress.refresh(targets, current)
	var target_coin: TextureRect = $Layout/Board/TargetHeader/TargetCoin
	target_coin.texture = _big_coin(targets[current])
	target_coin.get_node("Number").text = str(targets[current])
	$Layout/Board/TargetHeader/UnlockHint.text = "进入下一关" if current == 4 else "解锁新槽位"
	if game.guide_step == -1:
		hint.text = _toast_message if not _toast_message.is_empty() else tr("第 %d 关 · 点击同级硬币进行整理") % game.level


func _start_decorations() -> void:
	# 原版 CellLayer：两侧箭头在 ±6 之间往返，各 0.6 秒。
	for side: String in ["LeftArrow", "RightArrow"]:
		var arrow: TextureRect = $Layout/Board/TargetHeader.get_node(side + "/Icon")
		var direction := 1.0 if side == "LeftArrow" else -1.0
		arrow.position.x = 6.0 * direction
		var tween := create_tween().set_loops()
		tween.tween_property(arrow, "position:x", -6.0 * direction, 0.6)
		tween.tween_property(arrow, "position:x", 6.0 * direction, 0.6)
		_decoration_tweens.append(tween)


func _big_coin(value: int) -> Texture2D:
	return load(ROOT + "sprites/Texture/skin/big/BigCoin%d.png" % SlotView.skin_level(value))


func _can_interact() -> bool:
	return not _busy and not _leaving and not settings_dialog.visible and not _dialog.visible and not _congrats.visible


func _refresh_actions() -> void:
	var active := _can_interact()
	settings_button.disabled = not active
	deal_button.disabled = not active or (game.guide_step >= 0 and game.guide_step not in [3, 10]) or not game.can_deal()
	deal_button.modulate = Color.WHITE if not deal_button.disabled else Color(0.65, 0.72, 0.8, 0.75)
	if not active:
		_tutorial.hide()


func _on_slot_pressed(index: int) -> void:
	if not _can_interact():
		return
	if game.guide_step >= 0 and GUIDE_SLOTS.get(game.guide_step, -1) != index:
		return
	match game.cells[index].state:
		Rules.CellState.LOCKED, Rules.CellState.LOCK_AD:
			slots[index].lock_feedback()
			return
		Rules.CellState.UNLOCKABLE:
			_unlock_slot(index)
			return
		Rules.CellState.REWARD:
			_reward_cell = index
			_request_reward("normalTempItem")
			return
	if _selected == index:
		_sound("chooseCoin")
		_vibrate(15)
		_cancel_selection()
		return
	if _selected < 0:
		var count := game.selected_count(index)
		if count == 0:
			return
		_selected = index
		slots[index].select_coins(count)
		_sound("chooseCoin")
		_vibrate(15)
		if game.guide_step in [0, 4, 6]:
			game.guide_step += 1
		_update_tutorial()
		return
	_move_selected(index)


func _cancel_selection() -> void:
	if _selected >= 0:
		slots[_selected].select_coins(0)
	_selected = -1


func _move_selected(target: int) -> void:
	var source := _selected
	_vibrate(15)
	var result := game.move(source, target)
	if result.is_empty():
		_busy = true
		var shake: Tween = slots[source].shake_selected()
		_selected = -1
		_sound("warn")
		_refresh_actions()
		await shake.finished
		_after_action()
		return
	_busy = true
	_selected = -1
	var flying: Array = slots[source].take_tail(result.count, effects)
	if game.guide_step == 1:
		game.guide_step = 2
	elif game.guide_step == 5:
		game.guide_step = 6
	elif game.guide_step == 7:
		game.guide_step = 8
	# Retain the source views so hidden coins can turn over instead of popping.
	slots[source].select_coins(0)
	slots[target].render(game.cells[target], 0, false, game.can_merge(target))
	slots[target].hide_tail(result.count)
	_refresh_actions()
	_save_board()
	_action_tween = create_tween().set_parallel(true)
	slots[source].reveal_coins(result.revealed, game.cells[source], _action_tween)
	for offset in range(flying.size()):
		var view: TextureRect = flying[offset]
		var destination: Vector2 = slots[target].global_position + SlotView.coin_position(result.target_start + offset)
		var duration := clampf(view.global_position.distance_to(destination) / 1500.0, 0.05, 0.25)
		var delay := 0.035 * (flying.size() - offset - 1)
		_action_tween.tween_property(view, "global_position", destination, duration).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_action_tween.tween_callback(_sound.bind("placeCoin")).set_delay(delay + duration)
	await _action_tween.finished
	for view: TextureRect in flying:
		view.queue_free()
	_after_action()


func _on_deal_pressed() -> void:
	if not _can_interact() or deal_button.disabled:
		return
	_busy = true
	_cancel_selection()
	var first_deal := game.guide_step == 3
	var incoming := game.tutorial_deal() if game.guide_step in [3, 10] else game.deal()
	if first_deal:
		game.guide_step = 4
	elif game.guide_step == 10:
		game.finish_tutorial()
	_render_all()
	_save_board()
	_play_click()
	_sound("giveCoin")
	_vibrate(15)
	if incoming.is_empty():
		_after_action()
		return
	_action_tween = create_tween().set_parallel(true)
	var flying: Array[TextureRect] = []
	var origin := deal_button.global_position + deal_button.size / 2.0 - Vector2(50.5, 33.5)
	for index: int in incoming:
		var count: int = incoming[index].size()
		slots[index].hide_tail(count)
		var start: int = game.cells[index].coins.size() - count
		for offset in range(count):
			var item: Dictionary = incoming[index][offset]
			var boundary: bool = item.hidden and offset + 1 < count and not incoming[index][offset + 1].hidden
			var view := SlotView.make_coin(item, boundary)
			effects.add_child(view)
			view.global_position = origin
			flying.append(view)
			var destination: Vector2 = slots[index].global_position + SlotView.coin_position(start + offset)
			_action_tween.tween_property(view, "global_position", destination, 0.3).set_delay(0.035 * offset).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _action_tween.finished
	for view: TextureRect in flying:
		view.queue_free()
	_after_action()


func _after_action() -> void:
	_busy = false
	_render_all()
	_update_tutorial()
	_save_board()
	_settle_board()


func _settle_board() -> void:
	_refresh_actions()
	if not _can_interact():
		return
	if not game.mergeable_cells().is_empty():
		_schedule_auto_merge()
	elif game.is_failed():
		_schedule_failure()


func _schedule_auto_merge() -> void:
	if _auto_pending:
		return
	_auto_pending = true
	var generation := _board_generation
	_auto_tween = create_tween()
	_auto_tween.tween_interval(0.5)
	_auto_tween.tween_callback(_on_auto_merge_timeout.bind(generation))


func _on_auto_merge_timeout(generation: int) -> void:
	if generation != _board_generation:
		return
	_auto_pending = false
	if _can_interact() and not game.mergeable_cells().is_empty():
		_auto_merge()


func _auto_merge() -> void:
	_busy = true
	_cancel_selection()
	var previous_stage := game.stage()
	var merged := game.merge_ready()
	var maximum := 1
	for entry: Dictionary in merged:
		maximum = maxi(maximum, entry.level)
	var upgrade := game.check_upgrade(maximum)
	if game.guide_step == 2:
		game.guide_step = 3
	elif game.guide_step == 8:
		game.guide_step = 9
	# Settle and save immediately; retain the old visual board until celebration ends.
	_pending_next_level = upgrade.get("next_level", false)
	_holding_board = _pending_next_level
	_save_board()
	_refresh_actions()
	_sound("merge")
	_vibrate(200)
	_action_tween = create_tween().set_parallel(true)
	for entry: Dictionary in merged:
		slots[entry.index].merge_into(entry.level, _action_tween)
	if merged.size() > 1:
		_action_tween.tween_callback(_show_combo.bind(merged.size())).set_delay(0.35)
	await _action_tween.finished
	if not upgrade.is_empty():
		if _pending_next_level:
			if not await FX.fly_to_target(effects, maximum, _progress.targets[4].global_position + Vector2(28, 28)):
				return
			if not await _progress.advance(4, true):
				return
			_sound("win")
			FX.fireworks(effects)
		else:
			_sound("unlockArea")
			if not await _progress.advance(previous_stage):
				return
			_render_all()
		if _pending_next_level or upgrade.stage in [2, 4]:
			_congrats.open(maximum, _pending_next_level)
		else:
			_toast("新槽位已就绪，点击发光的锁开启")
	_after_action()


func _show_combo(count: int) -> void:
	_sound("combo")
	FX.combo(effects, count)


func _on_congrats_dismissed() -> void:
	if _pending_next_level:
		_busy = true
		await _transition_board(false)
		_pending_next_level = false
	_after_action()


func _transition_board(horizontal: bool) -> void:
	for effect in effects.get_children():
		effect.queue_free()
	var board: Control = $Layout/Board
	var origin := board.position
	_old_board = board.duplicate(0)
	_old_board.name = "DepartingBoard"
	board.get_parent().add_child(_old_board)
	board.get_parent().move_child(_old_board, board.get_index())
	_holding_board = false
	_render_all()
	var travel := Vector2(750, 0) if horizontal else Vector2(0, -1334)
	board.position = origin + travel
	_action_tween = create_tween().set_parallel(true)
	_action_tween.tween_property(_old_board, "position", origin - travel, 0.8)
	_action_tween.tween_property(board, "position", origin, 0.8)
	await _action_tween.finished
	_old_board.queue_free()
	_old_board = null


func _unlock_slot(index: int, reward: bool = false) -> void:
	_busy = true
	_cancel_selection()
	_refresh_actions()
	_sound("getArea")
	var opening: Tween = slots[index].play_open(reward)
	await opening.finished
	game.unlock_cell(index, reward)
	_save_board()
	_after_action()


func _schedule_failure() -> void:
	if _failure_pending:
		return
	_failure_pending = true
	var generation := _board_generation
	_failure_tween = create_tween()
	_failure_tween.tween_interval(0.3)
	_failure_tween.tween_callback(_on_failure_timeout.bind(generation))


func _on_failure_timeout(generation: int) -> void:
	if generation != _board_generation:
		return
	_failure_pending = false
	if _can_interact() and game.is_failed() and not _auto_pending:
		_show_failure()


func _show_failure() -> void:
	_cancel_selection()
	var actions: Array = []
	if game.shuffle_left > 0:
		actions.append({"id": "rescue", "label": tr("整理（剩余 %d 次）") % game.shuffle_left, "primary": true})
	actions.append({"id": "retry", "label": "重新挑战"})
	_dialog.open("槽位已满", "整理同级硬币释放空间，或重新挑战当前关卡。", actions, game.targets()[game.stage()])
	_refresh_actions()


func _on_dialog_action(action: String) -> void:
	_play_click()
	match action:
		"rescue":
			if game.shuffle_left == 3:
				_rescue()
			else:
				_request_reward("normalShuffle")
		"retry":
			_on_retry_requested()
		_:
			_dialog.hide()
			_after_action()


func _rescue(earned: bool = false) -> void:
	if not game.rescue(earned):
		return
	_dialog.hide()
	_busy = true
	_selected = -1
	_save_board()
	_sound("resetStart")
	var groups := {}
	for slot in slots:
		var views: Array = slot.take_tail(slot.coin_views.size(), effects)
		for view: TextureRect in views:
			var value: int = view.item.level
			if not groups.has(value):
				groups[value] = []
			groups[value].append(view)
	_render_all()
	_action_tween = create_tween().set_parallel(true)
	var flying: Array = []
	for index: int in game.normal_order:
		slots[index].hide_tail(slots[index].coin_views.size())
		for offset in range(game.cells[index].coins.size()):
			var item: Dictionary = game.cells[index].coins[offset]
			var view: TextureRect = groups[item.level].pop_front()
			flying.append(view)
			var delay := 0.035 * offset
			if view.item.hidden:
				view.reveal(_action_tween, item, delay)
			_action_tween.tween_property(view, "global_position", slots[index].global_position + SlotView.coin_position(offset), 0.3).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for group: Array in groups.values():
		for view: TextureRect in group:
			flying.append(view)
			_action_tween.tween_property(view, "modulate:a", 0.0, 0.3)
	_action_tween.tween_interval(0.3)
	await _action_tween.finished
	for view: TextureRect in flying:
		view.queue_free()
	_after_action()


func _request_reward(placement: String) -> void:
	if not _reward_placement.is_empty():
		return
	_reward_placement = placement
	_busy = true
	_refresh_actions()
	var completion := complete_reward.bind(_board_generation)
	if bypass_reward_ads:
		completion.call(true)
	elif reward_requested.get_connections().is_empty():
		completion.call(false)
	else:
		reward_requested.emit(placement, completion)


func complete_reward(earned: bool, generation: int) -> void:
	if _reward_placement.is_empty() or _leaving or generation != _board_generation:
		return
	var placement := _reward_placement
	_reward_placement = ""
	_busy = false
	if earned:
		if placement == "normalTempItem":
			var index := _reward_cell
			_reward_cell = -1
			_unlock_slot(index, true)
		elif placement == "normalShuffle":
			_rescue(true)
	else:
		_toast("奖励未完成，请稍后再试")
		_refresh_actions()


func _update_tutorial() -> void:
	var step := game.guide_step
	var message := ""
	match step:
		0: message = "normal.guide.tap_select"
		1: message = "normal.guide.same_type"
		3, 10: message = "normal.guide.get_more"
		4: message = "normal.guide.keep_merge"
		9: message = "normal.guide.merge_target"
	var rect := Rect2()
	var expected: int = GUIDE_SLOTS.get(step, -1)
	for index in range(slots.size()):
		slots[index].set_guided(expected == index)
	if expected >= 0:
		rect = slots[expected].get_global_rect().grow(6)
	elif step in [3, 10]:
		rect = deal_button.get_global_rect().grow(8)
	elif step == 9:
		rect = _progress.targets[4].get_global_rect().grow_individual(20, 58, 20, 15)
	_tutorial.focus(step, rect, message, _can_interact())
	if step >= 0:
		hint.text = ""
	_refresh_actions()


func _on_tutorial_activated(step: int) -> void:
	if step != game.guide_step or not _can_interact():
		return
	if step == 9:
		game.guide_step = 10
		_save_board()
		_update_tutorial()
	elif step in [3, 10]:
		_on_deal_pressed()
	elif GUIDE_SLOTS.has(step):
		_on_slot_pressed(GUIDE_SLOTS[step])


func _toast(message: String) -> void:
	_toast_generation += 1
	_toast_message = tr(message)
	hint.text = _toast_message
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.3)
	_toast_tween.tween_callback(_restore_hint.bind(_toast_generation))


func _restore_hint(generation: int) -> void:
	if generation == _toast_generation and not _leaving:
		_toast_message = ""
		_refresh_progress()
		_update_tutorial()


func _sound(sound_name: String) -> void:
	if not _settings.sound_enabled:
		return
	var path := ROOT + "audio/%s.mp3" % sound_name
	if not ResourceLoader.exists(path):
		return
	if not _sound_cache.has(sound_name):
		_sound_cache[sound_name] = load(path)
	var player := AudioStreamPlayer.new()
	player.stream = _sound_cache[sound_name]
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _save_board() -> void:
	if not game.save_game(save_path):
		push_warning("无法保存普通模式进度，本次运行仍可继续。")


func _animate_settings_button(pressed: bool) -> void:
	if not _can_interact():
		return
	if _button_tween:
		_button_tween.kill()
	_button_tween = create_tween()
	_button_tween.tween_property(settings_button, "scale", Vector2(0.9, 0.9) if pressed else Vector2.ONE, 0.08 if pressed else 0.12)


func _on_settings_button_pressed() -> void:
	if not _can_interact():
		return
	_play_click()
	_cancel_selection()
	if game.guide_step in [1, 5, 7]:
		game.guide_step -= 1
	if _button_tween:
		_button_tween.kill()
	settings_button.scale = Vector2.ONE
	settings_dialog.open_settings(_settings.sound_enabled, _settings.vibration_enabled, _settings.vibration_supported, true)
	_refresh_actions()


func _on_dialog_closed() -> void:
	if not _leaving:
		settings_button.grab_focus()
		_update_tutorial()
		_settle_board()


func _on_sound_toggled(enabled: bool) -> void:
	_settings.set_sound(enabled)


func _on_vibration_toggled(enabled: bool) -> void:
	_settings.set_vibration(enabled)


func _on_language_selected(locale: String) -> void:
	if _settings.set_language(locale):
		settings_dialog.set_language(_settings.language)
		_render_all()
		_update_tutorial()
		_play_click()


func _play_click() -> void:
	_sound("click")


func _vibrate(duration: int) -> void:
	if _settings.vibration_enabled and _settings.vibration_supported:
		Input.vibrate_handheld(duration)


func _on_retry_requested() -> void:
	if _busy or _leaving:
		return
	_busy = true
	_board_generation += 1
	_auto_pending = false
	_failure_pending = false
	for tween in [_auto_tween, _failure_tween]:
		if tween:
			tween.kill()
	_toast_message = ""
	_cancel_selection()
	_dialog.hide()
	settings_dialog.hide()
	game.restart()
	_save_board()
	await _transition_board(true)
	_after_action()


func _on_home_requested() -> void:
	if _leaving:
		return
	_leaving = true
	_save_board()
	settings_button.disabled = true
	settings_dialog.hide()
	_play_click()
	_return_tween = create_tween()
	_return_tween.tween_interval(0.15)
	_return_tween.tween_callback(_return_to_main_menu)


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		_leaving = false
		_refresh_actions()
		push_error("无法返回主界面：%s" % error_string(error))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _can_interact():
		get_viewport().set_input_as_handled()
		_on_settings_button_pressed()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED]:
		_save_board()


func _exit_tree() -> void:
	_save_board()
	_progress.stop()
	for tween in [_button_tween, _return_tween, _action_tween, _auto_tween, _failure_tween, _toast_tween] + _decoration_tweens:
		if tween:
			tween.kill()
