extends SceneTree
## Real viewport input, animations, completion, records, settings and resuming.

const Rules = preload("res://scripts/challenge_game.gd")
const NormalRules = preload("res://scripts/normal_game.gd")
const GAME_SCENE = preload("res://scenes/challenge.tscn")
const MENU_SCENE = preload("res://scenes/challenge_menu.tscn")
const SAVE := "user://challenge_ui_test.json"
const NORMAL_SAVE := "user://challenge_ui_normal_test.json"
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


func _click(control: Control, touch: bool = false) -> void:
	var at := control.get_global_rect().get_center()
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = at
		event.pressed = true
		root.push_input(event, true)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		root.push_input(event, true)
	else:
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
	while scene._busy:
		if Time.get_ticks_msec() > deadline:
			expect(false, "challenge action settles within eight seconds")
			return
		await process_frame
	await process_frame


func _capture(name: String) -> void:
	if not visual or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png("res://previews/challenge-%s.png" % name) == OK, "capture " + name)


func _make_scene(number: int = 1) -> void:
	Rules.requested_level = number
	scene = GAME_SCENE.instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await process_frame
	await _wait_idle()


func _free_scene() -> void:
	scene.queue_free()
	await process_frame
	await process_frame


func _normal_progress(highest: int) -> void:
	var normal := NormalRules.new()
	normal.highest_level = highest
	normal.save_game(NORMAL_SAVE)


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_normal_progress(1)
	await _test_menu()
	await _test_tutorial()
	await _test_moves_and_settings()
	await _test_completion_and_records()
	await _test_dense_board_and_exit()
	await _test_final_level()
	await _test_locked_success_and_interrupted_transition()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NORMAL_SAVE))
	print("CHALLENGE FLOW: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_menu() -> void:
	scene = MENU_SCENE.instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await process_frame
	expect(scene.cards.size() == 16 and not scene.cards[0].disabled and not scene.cards[1].disabled, "selection reads normal-mode history and shows sixteen clickable levels per page")
	await _capture("selection")
	await _click(scene.cards[1])
	expect(scene._unlock_dialog.visible and scene._unlock_number.text == "8", "locked card explains the required normal coin level")
	await _capture("unlock")
	await _drag_menu(Vector2(420, 360), Vector2(100, 360), true)
	expect(scene.page == 0 and scene._unlock_dialog.visible, "modal blocks swipes behind it")
	await _click(scene._unlock_dialog.get_node("Panel/Close"))
	expect(not scene._unlock_dialog.visible, "original-style close button dismisses the unlock prompt")
	await _click(scene.cards[1], true)
	expect(scene._unlock_dialog.visible, "a touch tap still opens its level after modal dismissal")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	await process_frame
	expect(not scene._unlock_dialog.visible, "escape dismisses the unlock prompt")
	await _drag_menu(Vector2(420, 360), Vector2(395, 360), true)
	expect(scene.page == 0 and is_zero_approx(scene._page_strip.position.x) and not scene._unlock_dialog.visible, "short touch drag springs back without opening its card")
	await _drag_menu(Vector2(420, 360), Vector2(420, 620), true)
	expect(scene.page == 0 and not scene._unlock_dialog.visible, "vertical movement neither pages nor opens a card")
	await _drag_menu(Vector2(420, 360), Vector2(100, 360), true)
	expect(scene.page == 1 and scene.cards[0].name == "Level17" and not scene._unlock_dialog.visible, "touch swipe follows the finger and selects the next page without opening a card")
	await _drag_menu(Vector2(420, 360), Vector2(100, 360), true, true)
	expect(scene.page == 1, "canceled touch returns to the current page")
	var secondary := InputEventScreenTouch.new()
	secondary.index = 1
	secondary.position = scene.cards[1].get_global_rect().get_center()
	secondary.pressed = true
	root.push_input(secondary, true)
	secondary = secondary.duplicate()
	secondary.pressed = false
	root.push_input(secondary, true)
	expect(scene.page == 1 and not scene._unlock_dialog.visible, "secondary touch cannot activate a card")
	for count in range(5):
		await _drag_menu(Vector2(420, 360), Vector2(100, 360), count % 2 == 0)
	expect(scene.page == 6 and scene.cards.size() == 5 and scene.cards.back().name == "Level101" and scene.cards.back().disabled, "swiping reaches all 100 levels and the unplayable Wait item")
	await _drag_menu(Vector2(420, 360), Vector2(100, 360), true)
	expect(scene.page == 6 and is_equal_approx(scene._page_strip.position.x, -6 * scene.GRID_SIZE.x), "last page resists overscroll and springs back")
	await _drag_menu(Vector2(160, 360), Vector2(500, 360))
	expect(scene.page == 5 and scene.cards[0].name == "Level81", "mouse drag navigates to the previous page")
	await _capture("selection-page-6")
	await _free_scene()
	scene = MENU_SCENE.instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await process_frame
	expect(scene.page == 0, "opening selection resets to the first page")
	await _drag_menu(Vector2(160, 360), Vector2(500, 360))
	expect(scene.page == 0 and is_zero_approx(scene._page_strip.position.x), "first page resists backward overscroll")
	await _free_scene()


func _drag_menu(start: Vector2, finish: Vector2, touch: bool = false, canceled: bool = false) -> void:
	var transform: Transform2D = scene.layout.get_global_transform_with_canvas()
	var event: InputEvent = InputEventScreenTouch.new() if touch else InputEventMouseButton.new()
	event.position = transform * start
	event.pressed = true
	if not touch:
		event.button_index = MOUSE_BUTTON_LEFT
	root.push_input(event, true)
	await process_frame
	var origin: float = scene._page_strip.position.x
	for step in range(1, 7):
		var motion: InputEvent = InputEventScreenDrag.new() if touch else InputEventMouseMotion.new()
		motion.position = transform * start.lerp(finish, step / 6.0)
		if not touch:
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
	if absf(finish.x - start.x) >= 88 and is_equal_approx(start.y, finish.y) and not scene._unlock_dialog.visible:
		expect(not is_equal_approx(scene._page_strip.position.x, origin), "page content tracks pointer movement before release")
	event = event.duplicate()
	event.position = transform * finish
	event.pressed = false
	if touch:
		event.canceled = canceled
	root.push_input(event, true)
	await create_timer(0.3).timeout


func _test_tutorial() -> void:
	await _make_scene()
	expect(scene.game.tutorial and scene.slots.size() == 3, "first entry displays the captured tutorial")
	expect(scene._intro_tween == null and scene._timer_label.text == "00:00", "tutorial is immediately visible and untimed")
	expect(not scene.slots[0].coin_views[0].number.visible and scene.slots[0].coin_views[0].icon.texture.resource_path.ends_with("war/War1.png"), "challenge uses the original color textures without numeral labels")
	await _capture("tutorial")
	await _click(scene.slots[0], true)
	expect(scene._selected == 0, "touch selects the top color group")
	await _click(scene.slots[0])
	expect(scene._selected == -1, "second click on source cancels selection")
	await _click(scene.slots[0])
	await _click(scene.slots[2])
	expect(scene._busy, "movement locks input while coins fly")
	scene._on_slot_pressed(1)
	await _wait_idle()
	expect(scene.game.cells[2].coins.size() == 3 and scene._selected == -1, "animation completes without accepting another selection")
	await _free_scene()
	await _make_scene()
	expect(scene.game.tutorial and scene.game.cells[2].coins.is_empty(), "leaving a tutorial restarts its unsaved practice board")
	scene._open_settings()
	var teaching_board: Array = scene.game.cells.duplicate(true)
	expect(not scene.settings_dialog.retry_button.disabled, "tutorial retry retains the original clickable button")
	await _click(scene.settings_dialog.retry_button)
	expect(scene.game.cells == teaching_board and not scene._busy, "tutorial ignores the retry event")
	scene.settings_dialog.dismiss()
	for pair: Array in [[0, 2], [1, 2], [1, 0], [2, 1]]:
		await _click(scene.slots[pair[0]])
		await _click(scene.slots[pair[1]])
		await _wait_idle()
	expect(scene.game.tutorial_done and not scene.game.tutorial and scene.slots.size() == 30, "finishing the tutorial enters the actual 6 by 5 first challenge")
	expect(scene.game.gold == 0 and scene.game.best_times.is_empty(), "tutorial transition grants no real-level reward")
	await _capture("level-1")
	await create_timer(0.12).timeout
	expect(scene.game.elapsed > 0 and scene._timer_label.text != "--:--", "formal challenge accumulates elapsed time")


func _cell(values: Array, target: int = 0) -> Dictionary:
	var stack: Array = []
	for value: Variant in values:
		stack.append(Rules.coin(value[0], value[1]) if value is Array else Rules.coin(value))
	return {"state": 0, "target": target, "coins": stack}


func _install(cells: Array) -> void:
	scene.game.cells = cells
	while scene.game.cells.size() < 30:
		scene.game.cells.append(_cell([]))
	scene.game.finished = false
	scene._build_board()


func _test_moves_and_settings() -> void:
	_install([_cell([1, 1, 1], 2), _cell([2, 2, 2, 2, 2, 2, 2], 1)])
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await _wait_idle()
	expect(scene.game.cells[0].coins.size() == 7 and scene.game.cells[1].coins.size() == 3, "GUI swaps unequal pure-color stacks")
	expect(scene.slots[0].coin_views.size() == 7 and scene.slots[1].coin_views.size() == 3, "swap leaves the rendered stacks aligned with logical state")
	_install([_cell([1, 2, 2, 2, 2], 1), _cell([2, 2, 2, 2, 2, 2, 2, 2, 2], 2)])
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await _wait_idle()
	expect(scene.game.cells[0].coins.size() == 4 and scene.game.cells[1].coins.size() == 10, "GUI permits partial movement without automatic merging")
	expect(scene.slots[1].tick.visible and not scene.slots[1].arrow.visible, "completed target shows a tick instead of the target arrow")
	await _click(scene.slots[1])
	expect(scene._selected == -1, "completed target rejects selection")
	_install([_cell([1, [3, true], [4, true], 2], 1), _cell([], 2)])
	await _click(scene.slots[0])
	await _click(scene.slots[1])
	await _wait_idle()
	expect(not scene.slots[0].coin_views[2].item.hidden and not scene.slots[0].coin_views[2].number.visible, "hidden segment flips to challenge textures without numbers")
	scene.game.start(1, false)
	scene._build_board()
	await _click(scene.slots[0])
	await _click(scene._settings_button)
	expect(scene.settings_dialog.visible and scene._selected == 0, "settings preserve the selected group")
	var time_in_settings: float = scene.game.elapsed
	await create_timer(0.12).timeout
	expect(scene.game.elapsed > time_in_settings and scene._selected == 0, "settings keep time running without dropping selection")
	await _click(scene.settings_dialog.retry_button)
	expect(scene._busy and not scene._time_running and scene.game.elapsed == 0, "retry stops time during the board transition")
	var old_board: Control = scene._surface.get_child(0)
	await create_timer(0.18).timeout
	expect(scene._surface.get_child_count() == 2 and old_board.position.x < 0 and scene._board.position.x > 0 and scene.game.elapsed == 0, "old and new boards slide horizontally before time starts")
	await _wait_idle()
	expect(not scene.settings_dialog.visible and scene._selected == -1 and scene.game.elapsed < 1.5, "settings retry generates a fresh board and resets elapsed time")
	var saved: Array = scene.game.cells.duplicate(true)
	scene.game.elapsed = 123.25
	await _free_scene()
	await _make_scene()
	expect(scene.game.cells == saved and scene.game.elapsed >= 123.25, "formal challenge resumes all coin stacks and elapsed time")
	expect(scene._intro_tween == null and not scene._busy, "resuming skips the entrance animation")
	var resumed_time: float = scene.game.elapsed
	await create_timer(0.12).timeout
	expect(scene.game.elapsed > resumed_time, "resumed time advances immediately")
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	scene._refresh_language()
	expect(scene._title.text == "Level1" and scene._progress_label.text.contains(" / "), "dynamic challenge labels update in English")
	await _capture("english")
	TranslationServer.set_locale(original_locale)
	scene._refresh_language()


func _test_completion_and_records() -> void:
	_normal_progress(8)
	scene.highest_coin = 8
	scene.game.cells = Rules.completed_cells(1)
	scene.game.cells[22].coins.append(scene.game.cells[0].coins.pop_back())
	scene.game.elapsed = 42
	scene._build_board()
	await _click(scene.slots[22])
	await _click(scene.slots[0])
	var celebration_deadline := Time.get_ticks_msec() + 4000
	while scene.layout.get_node_or_null("Fireworks") == null and Time.get_ticks_msec() < celebration_deadline:
		await process_frame
	await create_timer(0.2).timeout
	expect(scene.game.finished and scene._busy and not scene._dialog.visible and scene.layout.get_node_or_null("Fireworks") != null, "completion plays the board celebration and fireworks before its popup")
	await _wait_idle()
	expect(scene._dialog._actions.get_child_count() == 1 and scene._share_buttons[0].visible, "success offers one navigation action plus the original share entries")
	expect(scene.game.finished and scene._dialog.visible and scene.game.gold == 1, "last target stops the clock and opens the success dialog with one gold")
	var saved := Rules.new()
	expect(saved.load_game(SAVE) and saved.level == 2 and saved.cells.is_empty() and saved.best_times.has("1"), "success persists the record, reward and next level before offering continue")
	await _capture("success")
	await _click(scene._dialog._actions.get_child(0))
	expect(scene.game.elapsed == 0 and not scene._time_running, "next-level transition excludes all entrance time")
	await _wait_idle()
	expect(scene.game.level == 2 and scene.slots.size() == 35 and not scene._dialog.visible, "continue starts the unlocked next challenge")
	await _free_scene()
	var before := FileAccess.get_file_as_string(SAVE)
	await _make_scene(1)
	expect(scene._record_mode and not scene._dialog.visible and scene.game.level == 2, "completed level opens its solved board before the record popup")
	expect(not scene.slots[0].tick.visible and scene.slots.size() == 30, "record presentation displays the complete target layout")
	await _capture("record-board")
	await _click(scene._browse_button)
	expect(scene._dialog.visible, "tapping the completed board opens its record")
	await _capture("record")
	await _click(scene._dialog._close)
	expect(not scene._dialog.visible and scene._record_mode, "record close icon returns to the completed board")
	await _click(scene._browse_button)
	await _click(scene._dialog._actions.get_child(1))
	expect(not scene._dialog.visible and scene._record_mode, "closing record returns to the completed board")
	await _free_scene()
	expect(FileAccess.get_file_as_string(SAVE) == before, "inspecting a record preserves another level's in-progress save")
	await _make_scene(1)
	await _click(scene._browse_button)
	await _click(scene._dialog._actions.get_child(0))
	await _wait_idle()
	expect(not scene._record_mode and scene.game.level == 1 and scene.game.gold == 1 and scene.game.elapsed < 2, "record replay starts a fresh challenge while retaining the first reward")
	# Replaying with the next level unlocked must still offer Back, without reward.
	scene.game.cells = Rules.completed_cells(1)
	scene.game.cells[22].coins.append(scene.game.cells[0].coins.pop_back())
	scene._build_board()
	await _click(scene.slots[22])
	await _click(scene.slots[0])
	await _wait_idle()
	expect(scene._dialog._actions.get_child(0).text == TranslationServer.translate("challenge.back") and scene.game.gold == 1 and not scene._can_next, "replay completion offers Back and preserves the first reward")
	await _free_scene()


func _test_dense_board_and_exit() -> void:
	_normal_progress(598)
	await _make_scene(32)
	expect(scene.slots.size() == 208 and scene.game.dimensions() == Vector2i(16, 13), "largest captured layouts create all 208 interactive slots")
	await _capture("dense-board")
	var fitted: Vector2 = scene._board_size * scene._fit
	expect(scene._surface.size == Vector2(680, 1084) and fitted.x <= 681 and fitted.y <= 1085, "all 208 slots fit the original board area")
	await _free_scene()
	await _make_scene(1)
	if scene._record_mode:
		await _click(scene._browse_button)
		await _click(scene._dialog._actions.get_child(0))
		await _wait_idle()
	var source := 0
	var target := 22
	var count: int = scene.game.selected_count(source)
	var old_count: int = scene.game.cells[source].coins.size()
	await _click(scene.slots[source])
	await _click(scene.slots[target])
	expect(scene._busy, "exit test interrupts a live movement animation")
	await _free_scene()
	await _make_scene(1)
	expect(scene.game.cells[source].coins.size() == old_count - count and scene.game.cells[target].coins.size() == count, "leaving during a move restores the completed logical transaction")
	await _free_scene()


func _test_final_level() -> void:
	await _make_scene(100)
	scene.game.cells = Rules.completed_cells(100)
	var target := 0
	var source := -1
	for index in range(scene.game.cells.size()):
		if scene.game.cells[index].target <= 0:
			source = index
			break
	scene.game.cells[source].coins.append(scene.game.cells[target].coins.pop_back())
	scene.game.elapsed = 3661
	scene._build_board()
	# The last neutral cell may be offscreen after an accessibility focus change.
	scene._on_slot_pressed(source)
	scene._on_slot_pressed(target)
	await _wait_idle()
	expect(scene.game.finished and scene._dialog.visible and scene.game.best_times.has("100"), "last challenge completes with an hours-long elapsed time")
	expect(scene._dialog._actions.get_child(0).text == TranslationServer.translate("challenge.back"), "final challenge offers Back rather than nonexistent level 101")
	await _free_scene()


func _test_locked_success_and_interrupted_transition() -> void:
	# First completion with a locked next challenge uses the same Back branch.
	await _make_scene(2)
	scene.highest_coin = 8
	scene.game.cells = Rules.completed_cells(2)
	var empty := -1
	for index in range(scene.game.cells.size()):
		if scene.game.cells[index].target == 0:
			empty = index
			break
	scene.game.cells[empty].coins.append(scene.game.cells[0].coins.pop_back())
	scene._build_board()
	scene._on_slot_pressed(empty)
	scene._on_slot_pressed(0)
	await _wait_idle()
	expect(not scene._can_next and scene._dialog._actions.get_child(0).text == TranslationServer.translate("challenge.back"), "first win cannot continue into a locked level")
	await _free_scene()
	# A retry saved before the animation must remain playable if the scene exits.
	await _make_scene(1)
	await _click(scene._browse_button)
	await _click(scene._dialog._actions.get_child(0))
	expect(scene._busy and scene._surface.get_child_count() == 2, "record retry starts the two-board transition")
	var generated: Array = scene.game.cells.duplicate(true)
	await _free_scene()
	await _make_scene(1)
	expect(scene.game.cells == generated and scene._intro_tween == null and scene._time_running, "exiting during transition restores the new board immediately")
	await _free_scene()
