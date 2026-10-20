class_name GameSettings
extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const Localization = preload("res://scripts/localization.gd")
const LanguagePlatform = preload("res://scripts/language_platform.gd")

static var _shared: GameSettings

var sound_enabled := true
var vibration_enabled := true
var language := Localization.DEFAULT
var vibration_supported := false
var _config := ConfigFile.new()
var _settings_path := SETTINGS_PATH
var _has_language_preference := false
var _language_detection_started := false


# 两个场景持有同一个 RefCounted 对象，切换场景不丢失设置。
static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
	return _shared


func _init(path: String = SETTINGS_PATH) -> void:
	_settings_path = path
	if _config.load(_settings_path) != OK:
		_config.clear()
	var sound = _config.get_value("audio", "enabled", true)
	var vibration = _config.get_value("vibration", "enabled", true)
	var locale = _config.get_value("language", "locale", "")
	sound_enabled = sound if sound is bool else true
	vibration_enabled = vibration if vibration is bool else true
	_has_language_preference = locale is String and not Localization.normalize(locale).is_empty()
	language = Localization.available(locale) if _has_language_preference else Localization.DEFAULT
	vibration_supported = _supports_vibration()
	AudioServer.set_bus_mute(0, not sound_enabled)
	TranslationServer.set_locale(language)


func initialize_language(tree: SceneTree) -> void:
	if _has_language_preference or _language_detection_started:
		return
	_language_detection_started = true
	var detected := await _detect_language(tree)
	# A user may choose even the current English language while the SDK is pending.
	if not _has_language_preference:
		language = Localization.available(detected)
		TranslationServer.set_locale(language)


func _detect_language(tree: SceneTree) -> String:
	return await LanguagePlatform.get_language(tree)


func set_sound(enabled: bool) -> void:
	sound_enabled = enabled
	AudioServer.set_bus_mute(0, not enabled)
	_save()


func set_vibration(enabled: bool) -> void:
	vibration_enabled = enabled
	_save()
	if enabled and vibration_supported:
		Input.vibrate_handheld(15)


func set_language(locale: String) -> bool:
	var normalized := Localization.normalize(locale)
	if normalized.is_empty():
		return false
	var selected := Localization.available(normalized)
	var changed := selected != language
	_has_language_preference = true
	language = selected
	TranslationServer.set_locale(language)
	_save()
	return changed


func _save() -> void:
	_config.set_value("audio", "enabled", sound_enabled)
	_config.set_value("vibration", "enabled", vibration_enabled)
	if _has_language_preference:
		_config.set_value("language", "locale", language)
	elif _config.has_section_key("language", "locale"):
		_config.erase_section_key("language", "locale")
	if _config.save(_settings_path) != OK:
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
