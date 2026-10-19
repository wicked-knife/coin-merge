extends Control

const SETTINGS_PATH := "user://settings.cfg"

@onready var start_button: Button = $StartButton
@onready var challenge_button: Button = $ChallengeButton
@onready var settings_button: TextureButton = $SettingsButton
@onready var clouds: Control = $Clouds
@onready var click_sound: AudioStreamPlayer = $ClickSound
@onready var settings_dialog = $SettingsDialog

var _settings := ConfigFile.new()
var _sound_enabled := true
var _vibration_enabled := true
var _language := "zh"
var _vibration_supported := false
var _entry_finished := false
var _leaving := false
var _entry_tween: Tween
var _button_tweens: Dictionary = {}
var _previous_focus: Control


func _ready() -> void:
	_load_settings()
	_apply_language()
	_vibration_supported = _supports_vibration()
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
	_prepare_dialog()
	settings_dialog.open_notice("挑战模式暂未实现")


func _on_settings_button_pressed() -> void:
	if not _can_interact():
		return
	_prepare_dialog()
	settings_dialog.open_settings(_sound_enabled, _vibration_enabled, _vibration_supported)


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
	if _sound_enabled:
		click_sound.play()


# 设置只保存在本机；弹窗负责显示，主界面负责应用和保存。
func _load_settings() -> void:
	if _settings.load(SETTINGS_PATH) != OK:
		_settings.clear()
	var sound = _settings.get_value("audio", "enabled", true)
	var vibration = _settings.get_value("vibration", "enabled", true)
	var language = _settings.get_value("language", "locale", "zh")
	_sound_enabled = sound if sound is bool else true
	_vibration_enabled = vibration if vibration is bool else true
	_language = language if language is String and language in ["zh", "en"] else "zh"
	AudioServer.set_bus_mute(0, not _sound_enabled)


func _on_sound_toggled(enabled: bool) -> void:
	_sound_enabled = enabled
	AudioServer.set_bus_mute(0, not enabled)
	_save_settings()


func _on_vibration_toggled(enabled: bool) -> void:
	_vibration_enabled = enabled
	_save_settings()
	if enabled and _vibration_supported:
		Input.vibrate_handheld(15)


func _on_language_selected(locale: String) -> void:
	if locale not in ["zh", "en"] or locale == _language:
		return
	_language = locale
	_apply_language()
	_save_settings()
	_play_click()


func _apply_language() -> void:
	# Godot 会在语言变化时自动刷新场景中的按钮、Label 和悬停说明。
	TranslationServer.set_locale(_language)
	settings_dialog.set_language(_language)


func _save_settings() -> void:
	_settings.set_value("audio", "enabled", _sound_enabled)
	_settings.set_value("vibration", "enabled", _vibration_enabled)
	_settings.set_value("language", "locale", _language)
	if _settings.save(SETTINGS_PATH) != OK:
		push_warning("无法保存设置，本次运行仍然生效。")


func _supports_vibration() -> bool:
	if OS.has_feature("web"):
		return JavaScriptBridge.eval("typeof navigator.vibrate === 'function' && navigator.maxTouchPoints > 0") == true
	if OS.has_feature("android") and Engine.has_singleton("AndroidRuntime"):
		var context = Engine.get_singleton("AndroidRuntime").getApplicationContext()
		var vibrator = context.getSystemService("vibrator")
		return vibrator != null and vibrator.hasVibrator() and context.checkSelfPermission("android.permission.VIBRATE") == 0
	# 桌面及无法明确查询设备能力的平台隐藏振动选项。
	return false


func _exit_tree() -> void:
	if _entry_tween:
		_entry_tween.kill()
	for tween: Tween in _button_tweens.values():
		tween.kill()
