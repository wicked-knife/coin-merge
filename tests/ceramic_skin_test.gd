extends SceneTree
## Verify dynamic art families and produce review captures without writing player saves.
const Ceramic = preload("res://scripts/ceramic_skin.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Coin = preload("res://scripts/coin_visual.gd")
const Slot = preload("res://scripts/challenge_slot.gd")
var checks := 0
var failures := 0
var visual := false

class TemporarySettings extends "res://scripts/game_settings.gd":
	func _save() -> void:
		pass


func _initialize() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	call_deferred("_run")


func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)


func _run() -> void:
	var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Ceramic.ROOT + "palette.json"))
	for family in ["normal/%d.png", "war/War%d.png", "big/BigCoin%d.png"]:
		var count := 16 if family.begins_with("normal") else 11 if family.begins_with("war") else 15
		for number in range(1, count + 1):
			var path: String = Ceramic.SPRITES + "Texture/skin/" + family % number
			var texture := load(path) as Texture2D
			expect(texture != null, "dynamic texture loads: " + path)
			if texture:
				expect(texture.get_size() == (Vector2(164, 172) if count == 15 else Vector2(101, 67)), "coin canvas is unchanged")
	for number in range(1, 12):
		expect(Slot.COLORS[number].is_equal_approx(Color(palette.challenge[number - 1])), "target arrow uses generated coin palette %d" % number)
		var coin := load(Ceramic.SPRITES + "Texture/skin/war/War%d.png" % number) as Texture2D
		var face := coin.get_image().get_pixel(50, 24)
		var expected: Color = Slot.COLORS[number]
		expect(maxf(absf(face.r - expected.r), maxf(absf(face.g - expected.g), absf(face.b - expected.b))) < 0.12, "coin face matches target color %d" % number)
	var font_chars := Ceramic.FONT.base_font.get_supported_chars()
	expect(not Ceramic.FONT.base_font.allow_system_fallback, "base font does not depend on OS fallback")
	for fallback: FontFile in Ceramic.FONT.fallbacks:
		font_chars += fallback.get_supported_chars()
		expect(not fallback.allow_system_fallback, "bundled fallback does not depend on OS fallback")
	var csv := FileAccess.open("res://translations/menu.csv", FileAccess.READ)
	var missing := ""
	while not csv.eof_reached():
		var line := csv.get_csv_line()
		for field in line:
			for character in field:
				if character.unicode_at(0) >= 32 and character not in font_chars and character not in missing:
					missing += character
	expect(missing.is_empty(), "bundled font covers translation text: " + missing)
	if visual and DisplayServer.get_name() != "headless":
		await _capture_menus()
		await _capture_palette()
	print("CERAMIC ASSETS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _capture(name: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png("res://docs/reskin/after/%s.png" % name) == OK, "capture " + name)


func _capture_menus() -> void:
	var previous := Settings.shared()
	var locale := TranslationServer.get_locale()
	Settings._shared = TemporarySettings.new()
	for language in ["zh_CN", "en_US"]:
		Settings._shared.language = language
		TranslationServer.set_locale(language)
		var menu := preload("res://scenes/main_menu.tscn").instantiate()
		root.add_child(menu)
		await create_timer(1.5).timeout
		await _capture("menu-" + language)
		menu._on_settings_button_pressed()
		await _capture("settings-" + language)
		menu.queue_free()
		await process_frame
	Settings._shared = previous
	TranslationServer.set_locale(locale)


func _capture_palette() -> void:
	var canvas := Control.new()
	canvas.size = Vector2(750, 1334)
	canvas.theme = Theme.new()
	canvas.theme.default_font = Ceramic.FONT
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Ceramic.CREAM
	background.size = canvas.size
	canvas.add_child(background)
	for index in range(16):
		var coin := Coin.new()
		coin.configure({"level": index + 1, "hidden": index == 15}, index == 15)
		coin.position = Vector2(65 + (index % 4) * 166, 100 + (index / 4) * 130)
		canvas.add_child(coin)
	for index in range(11):
		var coin := Coin.new()
		coin.configure({"level": index + 1, "hidden": false}, false, true)
		coin.position = Vector2(65 + (index % 4) * 166, 690 + (index / 4) * 155)
		canvas.add_child(coin)
		var arrow := TextureRect.new()
		arrow.texture = preload(Ceramic.SPRITES + "Texture/skin/ColorArrow.png")
		arrow.modulate = Slot.COLORS[index + 1]
		arrow.position = coin.position + Vector2(35, 85)
		canvas.add_child(arrow)
	var label := Label.new()
	label.text = "合并硬币 / Coin Merge\n1  16  99  100  598  ·  ?"
	label.position = Vector2(45, 1200)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Ceramic.INK)
	canvas.add_child(label)
	await _capture("palette-and-glyphs")
	canvas.queue_free()
	await process_frame
