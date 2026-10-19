class_name GameSettings
extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"

static var _shared: GameSettings

var sound_enabled := true
var vibration_enabled := true
var language := "zh"
var vibration_supported := false
var _config := ConfigFile.new()


# 两个场景持有同一个 RefCounted 对象，切换场景不丢失设置。
static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
	return _shared


func _init() -> void:
	if _config.load(SETTINGS_PATH) != OK:
		_config.clear()
	var sound = _config.get_value("audio", "enabled", true)
	var vibration = _config.get_value("vibration", "enabled", true)
	var locale = _config.get_value("language", "locale", "zh")
	sound_enabled = sound if sound is bool else true
	vibration_enabled = vibration if vibration is bool else true
	language = locale if locale is String and locale in ["zh", "en"] else "zh"
	vibration_supported = _supports_vibration()
	AudioServer.set_bus_mute(0, not sound_enabled)
	TranslationServer.set_locale(language)


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
	if locale not in ["zh", "en"] or locale == language:
		return false
	language = locale
	TranslationServer.set_locale(language)
	_save()
	return true


func _save() -> void:
	_config.set_value("audio", "enabled", sound_enabled)
	_config.set_value("vibration", "enabled", vibration_enabled)
	_config.set_value("language", "locale", language)
	if _config.save(SETTINGS_PATH) != OK:
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
