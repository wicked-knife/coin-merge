extends SceneTree
## All-language resources, settings migration, SDK races and real modal input.
const Settings = preload("res://scripts/game_settings.gd")
const Languages = preload("res://scripts/localization.gd")
const Platform = preload("res://scripts/language_platform.gd")
const Rules = preload("res://scripts/challenge_game.gd")
const Normal = preload("res://scripts/normal_game.gd")
const Ceramic = preload("res://scripts/ceramic_skin.gd")
const CONFIG := "user://localization_test.cfg"
const SAVE := "user://localization_challenge_test.json"
const NORMAL_SAVE := "user://localization_normal_test.json"
var checks := 0
var failures := 0
var visual := false
var scene

class TemporarySettings extends "res://scripts/game_settings.gd":
	func _save() -> void:
		pass

class HostSettings extends "res://scripts/game_settings.gd":
	var host_value := "fr-CA"
	var delay := 0.06
	var calls := 0
	func _detect_language(tree: SceneTree) -> String:
		calls += 1
		await tree.create_timer(delay).timeout
		return host_value


func _initialize() -> void:
	visual = "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	call_deferred("_run")


func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)


func _run() -> void:
	var previous := Settings.shared()
	var previous_locale := TranslationServer.get_locale()
	var previous_mute := AudioServer.is_bus_mute(0)
	if "--narrow" in OS.get_cmdline_user_args():
		root.size = Vector2i(390, 844)
	_test_resources()
	await _test_settings()
	await _test_platform_timeout()
	Settings._shared = TemporarySettings.new(CONFIG)
	Settings._shared.sound_enabled = false
	Settings._shared.set_language("en_US")
	await _test_menu()
	await _test_normal()
	await _test_challenge_menu()
	await _test_challenge()
	await _test_records()
	Settings._shared = previous
	TranslationServer.set_locale(previous_locale)
	AudioServer.set_bus_mute(0, previous_mute)
	for path in [CONFIG, SAVE, NORMAL_SAVE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("LOCALIZATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_resources() -> void:
	var samples := {"en-us": "en_US", "en_GB": "en_US", "zh": "zh_CN", "zh_hant_HK": "zh_TW", "zh-TW": "zh_TW", "zh-HK": "zh_CN", "ko": "ko_KR", "in-ID": "id", "ms_MY": "id", "fr-CA": "fr", "de": "", "it": "", "hi": "", "": ""}
	for value: String in samples:
		expect(Languages.normalize(value) == samples[value], "normalize " + value)
	var file := FileAccess.open("res://translations/menu.csv", FileAccess.READ)
	var header := file.get_csv_line()
	var rows: Array = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == header.size():
			rows.append(row)
	var format := RegEx.new()
	format.compile("%[dsf]")
	var fonts: Array[Font] = [Ceramic.FONT.base_font]
	fonts.append_array(Ceramic.FONT.fallbacks)
	var chars := ""
	for font: FontFile in fonts:
		chars += font.get_supported_chars()
		expect(not font.allow_system_fallback, "bundled font excludes system fallback: " + font.resource_path)
	for item in Languages.LANGUAGES:
		var locale: String = item.locale
		expect(locale in TranslationServer.get_loaded_locales(), "loaded " + locale)
		TranslationServer.set_locale(locale)
		var column := header.find(locale)
		for row: PackedStringArray in rows:
			var message := str(TranslationServer.translate(row[0]))
			expect(message == row[column].replace("\\n", "\n"), "translation " + locale + ": " + row[0])
			expect(format.search_all(message).size() == format.search_all(row[header.find("en_US")]).size(), "format " + locale + ": " + row[0])
			for character in message:
				if character.unicode_at(0) >= 32:
					expect(character in chars, "glyph " + locale + ": " + character)
		for character in item.name:
			expect(character in chars, "native name glyph " + character)
	var french := load("res://translations/menu.fr.translation") as Translation
	TranslationServer.remove_translation(french)
	TranslationServer.set_locale("fr")
	expect(TranslationServer.translate("发牌") == "Deal", "missing translation falls back to English")
	expect(Languages.available("fr") == "en_US", "missing language resource selects English")
	TranslationServer.add_translation(french)


func _test_settings() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	var fresh := Settings.new(CONFIG)
	expect(fresh.language == "en_US", "fresh standalone default is English")
	await fresh.initialize_language(self)
	expect(fresh.language == "en_US", "standalone detection stays English")
	for legacy in ["zh", "en"]:
		var config := ConfigFile.new()
		config.set_value("language", "locale", legacy)
		config.set_value("audio", "enabled", false)
		config.save(CONFIG)
		var loaded := Settings.new(CONFIG)
		expect(loaded.language == ("zh_CN" if legacy == "zh" else "en_US") and not loaded.sound_enabled, "legacy preference " + legacy)
		loaded.set_language(loaded.language)
		config.load(CONFIG)
		expect(config.get_value("language", "locale") == loaded.language, "legacy value saved canonically")
	var saved := Settings.new(CONFIG)
	expect(saved.set_language("pt-BR"), "manual locale is normalized")
	var reloaded := Settings.new(CONFIG)
	expect(reloaded.language == "pt", "manual choice survives reload")
	expect(not reloaded.set_language("de") and reloaded.language == "pt", "unsupported manual choice is rejected")
	var preferred := HostSettings.new(CONFIG)
	await preferred.initialize_language(self)
	expect(preferred.calls == 0 and preferred.language == "pt", "saved preference skips host query")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	var host := HostSettings.new(CONFIG)
	host.initialize_language(self)
	host.initialize_language(self)
	await create_timer(0.12).timeout
	expect(host.calls == 1 and host.language == "fr", "host is detected once")
	expect(not FileAccess.file_exists(CONFIG), "automatic language is not saved as a manual choice")
	host.set_sound(false)
	var automatic := ConfigFile.new()
	automatic.load(CONFIG)
	expect(not automatic.has_section_key("language", "locale"), "audio changes do not persist an automatic language as a manual choice")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	var race := HostSettings.new(CONFIG)
	race.initialize_language(self)
	expect(not race.set_language("en_US"), "choosing current English still records user intent")
	await create_timer(0.12).timeout
	expect(race.language == "en_US", "late host result cannot overwrite manual English")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))
	var unsupported := HostSettings.new(CONFIG)
	unsupported.host_value = "hi-IN"
	await unsupported.initialize_language(self)
	expect(unsupported.language == "en_US", "unsupported host language uses English")


func _test_platform_timeout() -> void:
	var begin := func(): return true
	var pending := func(): return JSON.stringify({"done": false, "language": ""})
	var started := Time.get_ticks_msec()
	var language := await Platform.wait_for_language(self, begin, pending, 0.08)
	expect(language.is_empty() and Time.get_ticks_msec() - started >= 80 and Time.get_ticks_msec() - started < 500, "production polling times out without blocking startup")
	var ready := func(): return JSON.stringify({"done": true, "language": "ja"})
	expect(await Platform.wait_for_language(self, begin, ready) == "ja", "production poll reads completed SDK state")
	expect(await Platform.wait_for_language(self, func(): return false, pending) == "", "unavailable SDK exits immediately")


func _click(button: Control, touch: bool = false) -> void:
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


func _choose(dialog: Control, locale: String, touch: bool = false) -> void:
	await _click(dialog.language_button, touch)
	expect(dialog.language_dialog.visible and not dialog.panel.visible, "language modal replaces settings panel")
	var button: Button = dialog.language_dialog.buttons[locale]
	button.grab_focus()
	dialog.language_dialog.scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	await _click(button, touch)
	await process_frame
	expect(Settings.shared().language == locale and TranslationServer.get_locale() == locale, "pointer selects " + locale)
	expect(dialog.visible and dialog.panel.visible and not dialog.language_dialog.visible, "selection returns to settings")
	expect(dialog.language_button.text == Languages.native_name(locale), "settings shows native name " + locale)


func _capture(name: String) -> void:
	if not visual:
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews/localization"))
	expect(root.get_texture().get_image().save_png("res://previews/localization/" + name + ".png") == OK, "capture " + name)


func _check_modal_occlusion(slot: Control, panel: Control, context: String) -> void:
	if not visual:
		return
	await RenderingServer.frame_post_draw
	var shown := root.get_texture().get_image()
	var scale := Vector2(shown.get_size()) / root.get_visible_rect().size
	var overlap := slot.get_global_rect().intersection(panel.get_global_rect().grow(-40))
	var region := Rect2i(overlap.position * scale, overlap.size * scale)
	expect(region.size.x > 10 and region.size.y > 10, context + ": selected stack overlaps the opaque panel")
	if region.size.x <= 10 or region.size.y <= 10:
		return
	# Hiding a covered stack must not change the pixels inside the dialog.
	# This catches visual ordering independently of sibling order and input blocking.
	slot.hide()
	await RenderingServer.frame_post_draw
	var hidden := root.get_texture().get_image()
	slot.show()
	expect(shown.get_region(region).get_data() == hidden.get_region(region).get_data(), context + ": floating stack stays behind the dialog")
	await RenderingServer.frame_post_draw


func _dispose() -> void:
	scene.queue_free()
	await process_frame
	await process_frame


func _test_menu() -> void:
	scene = preload("res://scenes/main_menu.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.4).timeout
	await _click(scene.settings_button)
	await create_timer(0.25).timeout
	for index in range(Languages.LANGUAGES.size()):
		var locale: String = Languages.LANGUAGES[index].locale
		await _choose(scene.settings_dialog, locale, index % 2 == 0)
		await _capture("settings-" + locale)
		expect(scene.logo.texture == (scene.chinese_logo if locale.begins_with("zh_") else scene.english_logo), "logo " + locale)
		scene.settings_dialog.dismiss()
		await _capture("menu-" + locale)
		scene._on_settings_button_pressed()
		await create_timer(0.22).timeout
	scene.settings_dialog.open_language_picker()
	await _capture("language-picker")
	# Focus wrapping and touch scrolling must remain inside the nested modal.
	var picker = scene.settings_dialog.language_dialog
	expect(picker.buttons.zh_TW.get_node(picker.buttons.zh_TW.focus_next) == picker.close_button, "last language wraps keyboard focus to modal close")
	var initial_scroll: int = picker.scroll.scroll_vertical
	var start: Vector2 = picker.scroll.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.position = start
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	for index in range(1, 7):
		var drag := InputEventScreenDrag.new()
		drag.position = start + Vector2(0, index * 22)
		drag.relative = Vector2(0, 22)
		root.push_input(drag, true)
		await process_frame
	press.position = start + Vector2(0, 132)
	press.pressed = false
	root.push_input(press, true)
	await process_frame
	expect(picker.scroll.scroll_vertical < initial_scroll and picker.visible, "touch drag scrolls language list without selecting")
	var before := Settings.shared().language
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	expect(not scene.settings_dialog.language_dialog.visible and scene.settings_dialog.visible and Settings.shared().language == before, "Escape closes only language list")
	await _dispose()


func _test_normal() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NORMAL_SAVE))
	scene = preload("res://scenes/game.tscn").instantiate()
	scene.save_path = NORMAL_SAVE
	root.add_child(scene)
	await create_timer(0.15).timeout
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await _capture("normal-tutorial-" + item.locale)
	await _click(scene.slots[0])
	await create_timer(0.15).timeout
	var selected: int = scene._selected
	var board: Array = scene.game.cells.duplicate(true)
	var coin: TextureRect = scene.slots[0].coin_views[0]
	scene._on_settings_button_pressed()
	await create_timer(0.25).timeout
	await _check_modal_occlusion(scene.slots[0], scene.settings_dialog.panel, "normal settings")
	await _capture("normal-selected-settings")
	await _click(scene.settings_dialog.language_button)
	await _check_modal_occlusion(scene.slots[0], scene.settings_dialog.language_dialog.scroll, "normal language picker")
	await _capture("normal-selected-language-picker")
	scene.settings_dialog.language_dialog.dismiss()
	for item in Languages.LANGUAGES:
		await _choose(scene.settings_dialog, item.locale, true)
		expect(scene._selected == selected and scene.game.guide_step == 1 and scene.game.cells == board and scene.slots[0].coin_views[0] == coin, "normal selection, guide and coin identity survive " + item.locale)
	scene.settings_dialog.dismiss()
	expect(scene._selected == selected and scene.game.guide_step == 1 and scene.slots[0].coin_views[0] == coin, "closing settings restores the selected tutorial stack")
	scene.game.guide_step = -1
	scene._toast("奖励未完成，请稍后再试")
	Settings.shared().set_language("ru")
	await process_frame
	expect(scene.hint.text == TranslationServer.translate("奖励未完成，请稍后再试"), "active toast translates from original key")
	scene._show_failure()
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await process_frame
		expect(scene._dialog._action_note.text == TranslationServer.translate("本局剩余%d次") % scene.game.shuffle_left, "rescue note refresh " + item.locale)
		var body: Label = scene._dialog._body
		expect(body.position.y + body.get_minimum_size().y <= scene._dialog._note_row.position.y, "rescue text clears remaining count " + item.locale)
		await _capture("normal-rescue-" + item.locale)
	await _dispose()


func _test_challenge_menu() -> void:
	var normal := Normal.new()
	normal.highest_level = 1
	normal.save_game(NORMAL_SAVE)
	scene = preload("res://scenes/challenge_menu.tscn").instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await process_frame
	scene._settle_page(2)
	await create_timer(0.3).timeout
	var card: Button = scene.cards[0]
	scene._open_settings()
	await create_timer(0.25).timeout
	for item in Languages.LANGUAGES:
		await _choose(scene.settings_dialog, item.locale)
		expect(scene.page == 2 and scene.cards[0] == card, "page and card identity survive " + item.locale)
	scene.settings_dialog.dismiss()
	scene._open_level(33)
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await process_frame
		expect(scene._unlock_message.text == TranslationServer.translate("challenge.unlock_body") % Rules.config(33).unlock, "full unlock sentence " + item.locale)
		await _capture("challenge-locked-" + item.locale)
	await _click(scene._unlock_dialog.get_node("Panel/Close"))
	expect(not scene._unlock_dialog.visible, "locked dialog X closes through pointer")
	await _dispose()


func _test_challenge() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Rules.requested_level = 1
	scene = preload("res://scenes/challenge.tscn").instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await process_frame
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await process_frame
		expect(scene._hint.text == str(TranslationServer.translate("challenge.tutorial_hint")).replace("\\n", "\n") and scene.game.tutorial, "challenge tutorial refresh " + item.locale)
		await _capture("challenge-tutorial-" + item.locale)
	await _dispose()
	var normal := Normal.new()
	normal.highest_level = 598
	normal.save_game(NORMAL_SAVE)
	var progress := Rules.new()
	progress.start(1, false)
	progress.save_game(SAVE)
	Rules.requested_level = 1
	scene = preload("res://scenes/challenge.tscn").instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await create_timer(0.1).timeout
	while scene._busy:
		await process_frame
	var selected_index: int = scene.game.dimensions().x + 2
	scene._on_slot_pressed(selected_index)
	var selected: int = scene._selected
	expect(selected == selected_index, "challenge selects a stack overlapping the modal")
	var coin: TextureRect = scene.slots[selected_index].coin_views[0]
	var board: Array = scene.game.cells.duplicate(true)
	scene._open_settings()
	await create_timer(0.25).timeout
	await _check_modal_occlusion(scene.slots[selected_index], scene.settings_dialog.panel, "challenge settings")
	await _click(scene.settings_dialog.language_button)
	await _check_modal_occlusion(scene.slots[selected_index], scene.settings_dialog.language_dialog.scroll, "challenge language picker")
	scene.settings_dialog.language_dialog.dismiss()
	for item in Languages.LANGUAGES:
		await _choose(scene.settings_dialog, item.locale, true)
		expect(scene.game.cells == board and scene._selected == selected and scene.slots[selected_index].coin_views[0] == coin and scene._time_running, "challenge board and clock survive " + item.locale)
	scene.settings_dialog.dismiss()
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await _capture("challenge-board-" + item.locale)
	scene._time_running = false
	scene._open_success({"first": true, "record": true, "time": 65.0, "best": 65.0})
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await process_frame
		expect(scene._dialog._result_time.text == Rules.format_result_time(65), "result time units refresh " + item.locale)
		await _capture("challenge-result-" + item.locale)
	await _dispose()


func _test_records() -> void:
	var progress := Rules.new()
	progress.start(2, false)
	progress.best_times["1"] = 3661.0
	progress.save_game(SAVE)
	var saved := FileAccess.get_file_as_string(SAVE)
	Rules.requested_level = 1
	scene = preload("res://scenes/challenge.tscn").instantiate()
	scene.save_path = SAVE
	scene.normal_save_path = NORMAL_SAVE
	root.add_child(scene)
	await process_frame
	scene._open_settings()
	await create_timer(0.25).timeout
	var board: Array = scene.game.cells.duplicate(true)
	for item in Languages.LANGUAGES:
		await _choose(scene.settings_dialog, item.locale)
		expect(scene._record_mode and scene.game.cells == board and scene._timer_label.text == Rules.format_time(3661), "record board and localized timer survive " + item.locale)
	scene.settings_dialog.dismiss()
	scene._open_record()
	for item in Languages.LANGUAGES:
		Settings.shared().set_language(item.locale)
		await process_frame
		expect(scene._dialog._result_time.text == Rules.format_result_time(3661), "record duration refresh " + item.locale)
		await _capture("challenge-record-" + item.locale)
	expect(FileAccess.get_file_as_string(SAVE) == saved, "record localization preserves the other in-progress game on disk")
	await _dispose()
