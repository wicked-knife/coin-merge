extends Control

const SettingsStore = preload("res://scripts/game_settings.gd")

@export var chinese_logo: Texture2D
@export var english_logo: Texture2D

@onready var logo: TextureRect = $Logo
@onready var start_button: Button = $StartButton
@onready var challenge_button: Button = $ChallengeButton
@onready var settings_button: TextureButton = $SettingsButton
@onready var clouds: Control = $Clouds
@onready var click_sound: AudioStreamPlayer = $ClickSound
@onready var settings_dialog = $SettingsDialog

var _settings := SettingsStore.shared()
var _entry_finished := false
var _leaving := false
var _entry_tween: Tween
var _button_tweens: Dictionary = {}
var _previous_focus: Control


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	_settings.initialize_language(get_tree())
	_apply_language()
	for button: BaseButton in [start_button, challenge_button, settings_button]:
		button.button_down.connect(_animate_button.bind(button, true))
		button.button_up.connect(_animate_button.bind(button, false))
		button.mouse_exited.connect(_animate_button.bind(button, false))
	_on_resized()
	_play_entry()


# 云朵先进入，随后依次弹出挑战、开始和设置按钮。
func _play_entry() -> void:
	_entry_tween = create_tween().set_parallel(true)
	var offsets := [Vector2(0, 543), Vector2(330, 240), Vector2(-330, 240)]
	for index in range(clouds.get_child_count()):
		var cloud: Control = clouds.get_child(index)
		var target := cloud.position
		cloud.position += offsets[index]
		_entry_tween.tween_property(cloud, "position", target, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for button: Button in [challenge_button, start_button]:
		button.disabled = true
		button.scale = Vector2.ZERO
		button.modulate.a = 0.0
		var delay := 0.75 if button == challenge_button else 0.85
		_entry_tween.tween_property(button, "scale", Vector2.ONE, 0.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_entry_tween.tween_property(button, "modulate:a", 1.0, 0.3).set_delay(delay)
	settings_button.disabled = true
	settings_button.position.x = -settings_button.size.x
	settings_button.modulate.a = 0.0
	_entry_tween.tween_property(settings_button, "position:x", 24.5, 0.3).set_delay(0.95).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(settings_button, "modulate:a", 1.0, 0.3).set_delay(0.95)
	_entry_tween.finished.connect(_on_entry_finished)


func _on_entry_finished() -> void:
	_entry_finished = true
	for button: BaseButton in [start_button, challenge_button, settings_button]:
		button.disabled = false
	start_button.grab_focus()


func _on_resized() -> void:
	if not is_node_ready():
		return
	clouds.scale.x = size.x / 750.0
	for button: BaseButton in [start_button, challenge_button, settings_button]:
		button.pivot_offset = button.size / 2.0


func _animate_button(button: BaseButton, pressed: bool) -> void:
	if not _can_interact():
		return
	if _button_tweens.has(button):
		_button_tweens[button].kill()
	var tween := create_tween()
	var target := Vector2(0.9, 0.9) if pressed else Vector2.ONE
	tween.tween_property(button, "scale", target, 0.08 if pressed else 0.12)
	_button_tweens[button] = tween


func _can_interact() -> bool:
	return _entry_finished and not _leaving and not settings_dialog.visible


func _on_start_button_pressed() -> void:
	if not _can_interact():
		return
	_leaving = true
	_play_click()
	# 留出点击音效的播放时间，同时拒绝重复跳转。
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_challenge_button_pressed() -> void:
	if not _can_interact():
		return
	_leaving = true
	_play_click()
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/challenge_menu.tscn")


func _on_settings_button_pressed() -> void:
	if not _can_interact():
		return
	_prepare_dialog()
	settings_dialog.open_settings(_settings.sound_enabled, _settings.vibration_enabled, _settings.vibration_supported)


func _prepare_dialog() -> void:
	_play_click()
	_previous_focus = get_viewport().gui_get_focus_owner()
	for button: BaseButton in [start_button, challenge_button, settings_button]:
		if _button_tweens.has(button):
			_button_tweens[button].kill()
		button.scale = Vector2.ONE


func _on_dialog_closed() -> void:
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()
	else:
		start_button.grab_focus()


func _play_click() -> void:
	if _settings.sound_enabled:
		click_sound.play()


func _on_sound_toggled(enabled: bool) -> void:
	_settings.set_sound(enabled)


func _on_vibration_toggled(enabled: bool) -> void:
	_settings.set_vibration(enabled)


func _on_language_selected(locale: String) -> void:
	if not _settings.set_language(locale):
		return
	_apply_language()
	_play_click()


func _apply_language() -> void:
	# Godot 会在语言变化时自动刷新场景中的按钮、Label 和悬停说明。
	logo.texture = chinese_logo if SettingsStore.Localization.is_chinese(TranslationServer.get_locale()) else english_logo
	settings_dialog.set_language(_settings.language)
	preload("res://scripts/dialog_style.gd").refresh_text(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_language()


func _exit_tree() -> void:
	if _entry_tween:
		_entry_tween.kill()
	for tween: Tween in _button_tweens.values():
		tween.kill()
