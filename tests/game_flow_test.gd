extends SceneTree
## 真实视口输入、异步动画、存档和设置的贯通测试。-- --visual 可同时保存画面。

const SlotView = preload("res://scripts/coin_slot.gd")
const Rules = preload("res://scripts/normal_game.gd")
const GAME_SCENE = preload("res://scenes/game.tscn")
const SAVE := "user://normal_game_ui_test.json"

class SoundObservedGame extends "res://scripts/game.gd":
	var placement_times: Array[int] = []
	var sounds: Array[String] = []
	var vibrations: Array[int] = []

	func _sound(sound_name: String) -> void:
		sounds.append(sound_name)
		if sound_name == "placeCoin":
			placement_times.append(Time.get_ticks_msec())
		super._sound(sound_name)

	func _vibrate(duration: int) -> void:
		vibrations.append(duration)

var scene
var checks := 0
var failures := 0
var visual := false


func _initialize() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	await process_frame
	while scene._busy or scene._auto_pending or scene._failure_pending:
		if Time.get_ticks_msec() > deadline:
			expect(false, "game action must settle within eight seconds")
			return
		await process_frame
	await process_frame


func _capture(file: String) -> void:
	if not visual:
		return
	await create_timer(0.3).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://previews/%s.png" % file)
	expect(result == OK, "visual capture " + file)


func _capture_motion(label: String, frames: int, interval: float = 0.075) -> void:
	if not visual or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews/normal-alignment/" + label))
	for index in range(frames):
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://previews/normal-alignment/%s/%03d.png" % [label, index])
		expect(result == OK, "motion capture " + label)
		await create_timer(interval).timeout


func _make_scene() -> void:
	scene = GAME_SCENE.instantiate()
	scene.set_script(SoundObservedGame)
	scene.save_path = SAVE
	root.add_child(scene)
	await process_frame
	await process_frame


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await _make_scene()
	expect(scene.slots.size() == 12, "all twelve slots have interactive views")
	expect(scene.game.guide_step == 0 and scene.deal_button.disabled, "tutorial starts with deal disabled")
	await _capture("normal-mode-tutorial")
	await _click(scene.slots[1])
	expect(scene._selected == -1, "tutorial rejects wrong slot")
	await _click(scene.slots[0])
	expect(scene._selected == 0 and scene.game.guide_step == 1, "mouse selects first tutorial stack")
	await _click(scene.slots[2])
	expect(scene._busy and scene.game.cells[2].coins.size() == 10, "mouse transfers selected stack under input lock")
	scene._on_deal_pressed()
	expect(scene.game.cells[2].coins.size() == 10, "deal ignored during movement")
	await _wait_idle()
	expect(scene.game.guide_step == 3 and scene.game.cells[2].coins.size() == 2 and scene.game.cells[2].coins[0].level == 2, "automatic tutorial merge completes")
	expect(scene.placement_times.size() == 5, "moving five coins plays exactly five landing sounds")
	expect(scene.placement_times.back() - scene.placement_times.front() >= 60, "landing sounds follow staggered arrivals")
	await _click(scene.deal_button)
	await _wait_idle()
	expect(scene.game.guide_step == 4 and scene.game.cells[1].coins.size() == 4, "deal button receives GUI input and fixed tutorial deal")
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await _wait_idle()
	expect(scene.game.guide_step == 6 and scene.game.cells[1].coins.size() == 7, "second tutorial move creates seven coins")
	await _click(scene.slots[2])
	await _click(scene.slots[1])
	await _wait_idle()
	expect(scene.game.guide_step == 9 and scene._tutorial.visible and not scene._dialog.visible, "second merge focuses final target through tutorial mask")
	expect(scene.game.cells[1].coins.size() == 2 and scene.game.cells[1].coins[0].level == 3, "second merge produces two level 3 coins")
	await _capture("normal-mode-guide-complete")
	await _click(scene._tutorial)
	expect(scene.game.guide_step == 10 and not scene._dialog.visible, "target introduction advances through any tap")
	await _click(scene.deal_button)
	await _wait_idle()
	expect(scene.game.guide_step == -1 and not scene.deal_button.disabled, "tutorial ends and free play is enabled")
	expect(scene.game.cells[0].coins == [Rules.coin(2), Rules.coin(2), Rules.coin(2)] and scene.game.cells[1].coins.size() == 6 and scene.game.cells[2].coins == [Rules.coin(2)], "final tutorial deal still uses the fixed 3/4/1 configuration")
	await _click(scene.slots[11])
	expect(scene.slots[11].opening and not scene.game.is_playable(11), "reward slot is unavailable during cover motion")
	await _capture_motion("reward-open", 8)
	await _wait_idle()
	expect(scene.game.is_playable(11), "reserved reward slot works without ad dependency")
	await _capture("normal-mode-playing")
	await _test_free_play()
	await _test_detail_feedback()
	await _test_progress_and_failure()
	await _test_settings_and_save()
	await _test_exit_during_effects()
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("NORMAL GAME FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _set_board(stacks: Dictionary) -> void:
	scene.game.guide_step = -1
	scene._cancel_selection()
	for index: int in scene.game.normal_order:
		scene.game.cells[index].coins = []
	for index: int in stacks:
		scene.game.cells[index].coins = stacks[index].map(func(value: int) -> Dictionary: return Rules.coin(value))
	scene._render_all()
	scene._update_tutorial()


func _test_free_play() -> void:
	_set_board({0: [1, 2, 2, 2, 2], 1: [3, 3, 2, 2, 2, 2, 2, 2, 2]})
	var sound_count: int = scene.placement_times.size()
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await _capture_motion("invalid-move", 6, 0.05)
	await _wait_idle()
	expect(scene.game.cells[0].coins.size() == 4 and scene.game.cells[1].coins.size() == 10, "partial transfer works through actual GUI input")
	expect(scene.placement_times.size() - sound_count == 1, "partial transfer sounds only the coin that actually moves")
	await _click(scene.slots[0])
	await _click(scene.slots[0])
	expect(scene._selected == -1, "second click cancels selection in free play")
	_set_board({0: [1, 1, 1], 1: [2, 2]})
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await _wait_idle()
	expect(scene._selected == -1 and scene.game.cells[0].coins.size() == 3, "invalid move warns, clears selection and preserves coins")
	# Touch path is independent of mouse emulation and only primary touch is accepted.
	var touch := InputEventScreenTouch.new()
	touch.position = scene.slots[0].get_global_rect().get_center()
	touch.index = 1
	touch.pressed = true
	root.push_input(touch, true)
	expect(scene._selected == -1, "secondary touch is ignored")
	touch.index = 0
	root.push_input(touch, true)
	expect(scene._selected == 0, "primary touch selects a stack")
	touch.pressed = false
	root.push_input(touch, true)
	scene._cancel_selection()
	# 两个槽同时满十，必须批量合并而不是互相抢输入锁。
	_set_board({0: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 1: [2, 2, 2, 2, 2, 2, 2, 2, 2, 2]})
	scene._settle_board()
	await _wait_idle()
	expect(scene.game.cells[0].coins.size() == 2 and scene.game.cells[1].coins.size() == 2, "simultaneous merges settle in one batch")


func _test_progress_and_failure() -> void:
	_set_board({0: [4, 4, 4, 4, 4, 4, 4, 4, 4, 4]})
	scene._settle_board()
	var progress_sounds: int = scene.sounds.size()
	await _capture_motion("merge-progress", 18, 0.15)
	await _wait_idle()
	expect(scene.game.stage() == 1 and scene.game.cells[5].state == Rules.CellState.UNLOCKABLE, "automatic merge advances goal and grants slot eligibility")
	expect("unlockArea" in scene.sounds.slice(progress_sounds) and "getArea" not in scene.sounds.slice(progress_sounds), "stage qualification uses unlockArea")
	await _click(scene.slots[5])
	expect(not scene.game.is_playable(5) and scene.slots[5].opening, "yellow slot stays unavailable until opening finishes")
	await _capture_motion("yellow-open", 12)
	await _wait_idle()
	expect(scene.game.is_playable(5), "newly unlocked slot accepts click")
	expect(scene.sounds.back() == "getArea", "opening yellow slot uses getArea")
	# 满盘只在无空位且不可合并时判负。
	for index: int in scene.game.normal_order:
		scene.game.cells[index].coins = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2].map(func(value: int) -> Dictionary: return Rules.coin(value))
	scene._render_all()
	scene._settle_board()
	await _wait_idle()
	expect(scene._dialog.visible and scene.deal_button.disabled, "full mixed board shows failure modal")
	await _capture("normal-mode-rescue")
	await _click(scene._dialog._actions.get_child(0))
	await _capture_motion("rescue", 12)
	await _wait_idle()
	expect(scene.game.shuffle_left == 2 and not scene.game.is_failed(), "failure rescue frees capacity through merging")
	expect("resetStart" in scene.sounds and "reset" not in scene.sounds, "rescue uses resetStart")
	if scene._dialog.visible:
		await _click(scene._dialog._actions.get_child(0))
	# 验证第五目标切换下一大关，不以空盘或卡住结束。
	scene.game.unlock_count = 12
	_set_board({0: [9, 9, 9, 9, 9, 9, 9, 9, 9, 9]})
	scene._settle_board()
	await _capture_motion("final-win", 36, 0.15)
	await _wait_idle()
	expect(scene.game.level == 2 and scene._congrats.visible and scene.game.normal_order.size() == 6, "last target opens next playable major level")
	expect(scene._holding_board and scene.slots[0].coin_views.size() == 10 and scene._progress.current == 5, "new board remains hidden behind final celebration")
	await _capture("normal-mode-final-congrats")
	await _click(scene._congrats)
	await create_timer(0.25).timeout
	expect(is_instance_valid(scene._old_board) and scene._busy, "next level slides both old and new boards")
	await _capture_motion("next-board", 8)
	await _wait_idle()
	expect(scene._can_interact(), "continue after level completion returns control")


func _test_detail_feedback() -> void:
	_set_board({0: [1, 2, 2], 1: [3]})
	var sounds: int = scene.sounds.size()
	await _click(scene.slots[0])
	await create_timer(0.25).timeout
	var selected = scene.slots[0].coin_views.back()
	expect(selected.position.y < SlotView.coin_position(2).y - 30 and selected.content.position.y > 0, "selected coins lift 35 px and continuously float")
	await _capture_motion("selected", 10, 0.1)
	await _click(scene.slots[0])
	expect(scene.sounds.slice(sounds) == ["chooseCoin", "chooseCoin"], "select and cancel both play chooseCoin")
	expect(15 in scene.vibrations and 200 in scene.vibrations, "short and long haptics cover player actions and merge")
	var lock_origin: Vector2 = scene.slots[10].position
	sounds = scene.sounds.size()
	await _click(scene.slots[10])
	await create_timer(0.1).timeout
	expect(scene.slots[10].position == lock_origin and absf(scene.slots[10]._icon.rotation) > 0.01, "locked click rotates only the lock icon")
	expect(scene.sounds.size() == sounds, "locked click has no warning sound")
	await create_timer(0.5).timeout
	# A hidden segment has one question; preserve its old views through the flip.
	scene.game.cells[0].coins = [Rules.coin(1, true), Rules.coin(2, true), Rules.coin(3)]
	scene.game.cells[1].coins = []
	scene._render_all()
	expect(not scene.slots[0].coin_views[0].question.visible and scene.slots[0].coin_views[1].question.visible, "only hidden segment boundary carries a question mark")
	var hidden = scene.slots[0].coin_views[1]
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await create_timer(0.09).timeout
	expect(is_instance_valid(hidden) and hidden.scale.x < 0.7 and hidden.item.hidden, "hidden coin visibly shrinks before face replacement")
	await _capture_motion("reveal", 5, 0.04)
	await _wait_idle()
	expect(not scene.slots[0].coin_views[1].item.hidden and scene.slots[0].coin_views[1].number.visible, "revealed coins finish with level and number visible")
	# All full, including a pending merge: Deal must remain disabled in its delay.
	for index: int in scene.game.normal_order:
		scene.game.cells[index].coins = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2].map(func(v: int) -> Dictionary: return Rules.coin(v))
	scene.game.cells[0].coins = range(10).map(func(_v: int) -> Dictionary: return Rules.coin(1))
	scene._render_all()
	expect(scene.deal_button.disabled and not scene.game.is_failed(), "deal disabled for a full board even with a pending merge")
	sounds = scene.sounds.size()
	scene._on_deal_pressed()
	expect(scene.sounds.size() == sounds, "disabled deal emits no click or dealing sound")
	var border = scene.slots[0]._merge_copy
	await create_timer(0.2).timeout
	expect(border.visible and border.modulate.a > 0 and is_instance_valid(scene.slots[0]._merge_particles), "merge-ready border pulses with active particles")
	scene._settle_board()
	await _wait_idle()
	expect("merge" in scene.sounds.slice(sounds) and "getNewCoin" not in scene.sounds.slice(sounds), "single merge has no extra new-coin sound")


func _test_settings_and_save() -> void:
	await _click(scene.settings_button)
	expect(scene.settings_dialog.visible and scene.deal_button.disabled, "settings blocks board input")
	var previous_level: int = scene.game.level
	var sound_start: int = scene.sounds.size()
	await _click(scene.settings_dialog.retry_button)
	await create_timer(0.08).timeout
	expect(scene._busy and is_instance_valid(scene._old_board), "retry keeps both boards during horizontal transition")
	await _capture_motion("retry", 10)
	await _wait_idle()
	expect("resetStart" not in scene.sounds.slice(sound_start), "retry does not play rescue sound")
	expect(not scene.settings_dialog.visible and scene.game.level == previous_level and scene.game.shuffle_left == 3, "settings retry resets current board and preserves progress")
	var saved: Dictionary = scene.game.snapshot()
	scene.queue_free()
	await process_frame
	await _make_scene()
	expect(scene.game.snapshot() == saved, "reopening scene restores exact board and progress")


func _test_exit_during_effects() -> void:
	scene.game.level = 1
	scene.game.unlock_count = 5
	_set_board({0: [4, 4, 4, 4, 4, 4, 4, 4, 4, 4]})
	scene._settle_board()
	await create_timer(0.59).timeout
	expect(scene._busy and scene.game.stage() == 1, "stage settlement is saved while merge is still animating")
	scene.queue_free()
	await process_frame
	await _make_scene()
	expect(scene.game.stage() == 1 and scene.game.cells[0].coins == [Rules.coin(5), Rules.coin(5)], "exit during merge restores settled coins and unlock progress")
	scene.game.unlock_count = 12
	_set_board({0: [9, 9, 9, 9, 9, 9, 9, 9, 9, 9]})
	scene._settle_board()
	await create_timer(1.3).timeout
	expect(scene._holding_board and scene.game.level == 2 and scene.effects.has_node("FinalBigCoin"), "final board stays held while big coin is animating")
	scene.queue_free()
	await process_frame
	await _make_scene()
	expect(scene.game.level == 2 and not scene._holding_board and scene._can_interact(), "exit during final celebration restores playable next level")
	await create_timer(0.1).timeout
	expect(scene.effects.get_child_count() == 0, "reopened board has no stale visual effects")
