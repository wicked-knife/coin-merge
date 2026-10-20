extends Control
const Ceramic = preload("res://scripts/ceramic_skin.gd")
## Shared presentation and settings for challenge selection and play.

const SettingsStore = preload("res://scripts/game_settings.gd")
const DialogStyle = preload("res://scripts/dialog_style.gd")
const UI_ROOT := Ceramic.SPRITES
var layout: Control
var settings_dialog
var _settings := SettingsStore.shared()
var _sounds: Dictionary = {}
var _leaving := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Theme.new()
	theme.default_font = Ceramic.FONT
	theme.set_color("font_color", "Label", Ceramic.INK)
	theme.default_font_size = 28
	var background := texture(preload(UI_ROOT + "ui/BG.png"), Vector2.ZERO, size)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	layout = Control.new()
	layout.name = "Layout"
	layout.size = Vector2(750, 1334)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	resized.connect(_fit_layout)
	_fit_layout()
	settings_dialog = preload("res://scenes/settings_dialog.tscn").instantiate()
	settings_dialog.name = "SettingsDialog"
	settings_dialog.hide()
	layout.add_child(settings_dialog)
	settings_dialog.set_language(_settings.language)
	settings_dialog.sound_toggled.connect(_settings.set_sound)
	settings_dialog.vibration_toggled.connect(_settings.set_vibration)
	settings_dialog.language_selected.connect(_change_language)
	settings_dialog.feedback_requested.connect(_sound.bind("click"))
	settings_dialog.z_index = 30


func _fit_layout() -> void:
	var factor := minf(size.x / 750.0, size.y / 1334.0)
	layout.scale = Vector2.ONE * factor
	layout.position = (size - layout.size * factor) / 2.0


static func texture(image: Texture2D, at: Vector2, dimensions: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture = image
	view.position = at
	view.size = dimensions
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


func label(text: String, at: Vector2, dimensions: Vector2, font_size: int = 28) -> Label:
	var view := Label.new()
	view.text = text
	view.position = at
	view.size = dimensions
	view.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_theme_font_size_override("font_size", font_size)
	view.add_theme_color_override("font_color", Ceramic.INK)
	return view


func brighten(view: Label) -> void:
	view.add_theme_color_override("font_color", Ceramic.INK)
	view.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	view.add_theme_constant_override("shadow_offset_y", 2)


func button(text: String, at: Vector2, dimensions: Vector2, callback: Callable, green: bool = false) -> Button:
	var view := Button.new()
	view.text = text
	view.position = at
	view.size = dimensions
	DialogStyle.apply_button(view, "green" if green else "blue")
	view.pressed.connect(callback)
	return view


func settings_button(callback: Callable) -> TextureButton:
	var view := TextureButton.new()
	view.position = Vector2(34, 42)
	view.size = Vector2(82, 91)
	view.texture_normal = preload(UI_ROOT + "ui/Btn_Setting_2acdf23c.png")
	view.ignore_texture_size = true
	view.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	view.tooltip_text = "设置"
	view.pressed.connect(callback)
	layout.add_child(view)
	return view


func _change_language(locale: String) -> void:
	if _settings.set_language(locale):
		settings_dialog.set_language(locale)
		_refresh_language()


func _refresh_language() -> void:
	pass


func _sound(sound_name: String) -> void:
	if not _settings.sound_enabled:
		return
	if not _sounds.has(sound_name):
		var path := "res://assets/rea_original/audio/%s.mp3" % sound_name
		if not ResourceLoader.exists(path):
			return
		var player := AudioStreamPlayer.new()
		player.stream = load(path)
		add_child(player)
		_sounds[sound_name] = player
	_sounds[sound_name].play()


func _go_to(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	_sound("click")
	get_tree().call_deferred("change_scene_to_file", path)
