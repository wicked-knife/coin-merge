extends Control

const SettingsStore = preload("res://scripts/game_settings.gd")

@onready var settings_button: TextureButton = $Layout/TopBar/SettingsButton
@onready var click_sound: AudioStreamPlayer = $ClickSound
@onready var settings_dialog = $SettingsDialog

var _settings := SettingsStore.shared()
var _leaving := false
var _button_tween: Tween
var _return_tween: Tween


func _ready() -> void:
	settings_dialog.set_language(_settings.language)
	settings_button.pivot_offset = settings_button.size / 2.0
	settings_button.button_down.connect(_animate_settings_button.bind(true))
	settings_button.button_up.connect(_animate_settings_button.bind(false))
	settings_button.mouse_exited.connect(_animate_settings_button.bind(false))


func _animate_settings_button(pressed: bool) -> void:
	if _leaving or settings_dialog.visible:
		return
	if _button_tween:
		_button_tween.kill()
	_button_tween = create_tween()
	var target := Vector2(0.9, 0.9) if pressed else Vector2.ONE
	_button_tween.tween_property(settings_button, "scale", target, 0.08 if pressed else 0.12)


func _on_settings_button_pressed() -> void:
	if _leaving or settings_dialog.visible:
		return
	_play_click()
	if _button_tween:
		_button_tween.kill()
	settings_button.scale = Vector2.ONE
	settings_dialog.open_settings(_settings.sound_enabled, _settings.vibration_enabled, _settings.vibration_supported, true)


func _on_dialog_closed() -> void:
	if not _leaving:
		settings_button.grab_focus()


func _on_sound_toggled(enabled: bool) -> void:
	_settings.set_sound(enabled)


func _on_vibration_toggled(enabled: bool) -> void:
	_settings.set_vibration(enabled)


func _on_language_selected(locale: String) -> void:
	if _settings.set_language(locale):
		settings_dialog.set_language(_settings.language)
		_play_click()


func _play_click() -> void:
	if _settings.sound_enabled:
		click_sound.play()


func _on_home_requested() -> void:
	if _leaving:
		return
	_leaving = true
	settings_button.disabled = true
	settings_dialog.hide()
	_play_click()
	# 留出点击音效的播放时间，并拒绝重复跳转。
	_return_tween = create_tween()
	_return_tween.tween_interval(0.15)
	_return_tween.tween_callback(_return_to_main_menu)


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		_leaving = false
		settings_button.disabled = false
		settings_button.grab_focus()
		push_error("无法返回主界面：%s" % error_string(error))


func _exit_tree() -> void:
	if _button_tween:
		_button_tween.kill()
	if _return_tween:
		_return_tween.kill()
