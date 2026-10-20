extends SceneTree
## Real pointer input through settings above tutorial, formal, dense and record boards.

const Rules = preload("res://scripts/challenge_game.gd")
const NormalRules = preload("res://scripts/normal_game.gd")
const Settings = preload("res://scripts/game_settings.gd")
const GAME = preload("res://scenes/challenge.tscn")
const SAVE := "user://challenge_settings_input_test.json"
const NORMAL_SAVE := "user://challenge_settings_normal_test.json"

class TemporarySettings extends "res://scripts/game_settings.gd":
	func _save() -> void:
		pass

var checks := 0
var failures := 0
var scene


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _click(button: Control, touch: bool) -> void:
	var at := button.get_global_rect().get_center()
	var event: InputEvent
	if touch:
		event = InputEventScreenTouch.new()
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = at
		root.push_input(motion, true)
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _run() -> void:
	var original_settings := Settings.shared()
	var original_locale := TranslationServer.get_locale()
	var original_mute := AudioServer.is_bus_mute(0)
	var normal := NormalRules.new()
	normal.highest_level = 598
	normal.save_game(NORMAL_SAVE)
	if "--narrow" in OS.get_cmdline_user_args():
		root.size = Vector2i(390, 844)
	for mode in ["tutorial", "formal", "dense", "record"]:
		for touch in [false, true]:
			await _test_settings(mode, touch)
	TranslationServer.set_locale(original_locale)
	AudioServer.set_bus_mute(0, original_mute)
	expect(original_settings == Settings.shared(), "user settings singleton is preserved")
	for path in [SAVE, NORMAL_SAVE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CHALLENGE SETTINGS INPUT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_settings(mode: String, touch: bool) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var number := 32 if mode == "dense" else 1
	if mode != "tutorial":
		var progress := Rules.new()
		if mode == "record":
			progress.best_times["1"] = 42.0
		else:
			progress.start(number, false)
		progress.save_game(SAVE)
	Rules.requested_level = number
	scene = GAME.instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	scene._settings = TemporarySettings.new()
	scene._settings.set_language("zh_CN")
	scene._settings.sound_enabled = false
	TranslationServer.set_locale("zh_CN")
	root.add_child(scene)
	await process_frame
	await process_frame
	var board: Array = scene.game.cells.duplicate(true)
	var selected: int = scene._selected
	var dialog = scene.settings_dialog
	var context := "%s / %s" % [mode, "touch" if touch else "mouse"]
	await _click(scene._settings_button, touch)
	await create_timer(0.25).timeout
	expect(dialog.visible, context + ": settings open through the gear button")
	await _choose_language(dialog, "en_US", touch)
	if scene._settings.language != "en_US" and not touch:
		var hovered := root.gui_get_hovered_control()
		print("Blocked English button by: ", hovered.get_path() if hovered else "none")
	expect(scene._settings.language == "en_US" and TranslationServer.get_locale().begins_with("en"), context + ": English button changes the locale")
	expect(scene._title.text == "Level%d" % number and dialog.language_dialog.buttons.en_US.button_pressed, context + ": gameplay and selection update to English")
	expect(dialog.visible and scene.game.cells == board and scene._selected == selected, context + ": language change preserves the open modal and board")
	await _click(dialog.close_button, touch)
	expect(not dialog.visible and not scene._settings_button.disabled, context + ": X closes settings and restores the gear")
	if dialog.visible:
		dialog.dismiss()
	await _click(scene._settings_button, touch)
	await create_timer(0.25).timeout
	await _choose_language(dialog, "zh_CN", touch)
	expect(scene._settings.language == "zh_CN" and TranslationServer.get_locale().begins_with("zh") and scene._title.text == "关卡%d" % number, context + ": Chinese button restores Chinese gameplay")
	await _click(dialog.close_button, touch)
	expect(not dialog.visible and not scene._settings_button.disabled, context + ": X closes settings again after changing back")
	scene.queue_free()
	await process_frame
	await process_frame


func _choose_language(dialog: Control, locale: String, touch: bool) -> void:
	await _click(dialog.language_button, touch)
	var button: Button = dialog.language_dialog.buttons[locale]
	button.grab_focus()
	dialog.language_dialog.scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	await _click(button, touch)
