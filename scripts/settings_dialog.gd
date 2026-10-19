extends Control

signal closed
signal sound_toggled(enabled: bool)
signal vibration_toggled(enabled: bool)
signal language_selected(locale: String)
signal feedback_requested

@onready var panel: NinePatchRect = $Panel
@onready var title: Label = $Panel/Title
@onready var close_button: TextureButton = $Panel/CloseButton
@onready var options: VBoxContainer = $Panel/Options
@onready var sound_toggle: Button = $Panel/Options/SoundRow/Toggle
@onready var vibration_row: HBoxContainer = $Panel/Options/VibrationRow
@onready var vibration_toggle: Button = $Panel/Options/VibrationRow/Toggle
@onready var chinese_button: Button = $Panel/Options/LanguageRow/Languages/Chinese
@onready var english_button: Button = $Panel/Options/LanguageRow/Languages/English
@onready var message: Label = $Panel/Message

var _open_tween: Tween
var _toggle_tweens: Dictionary = {}
var _close_tween: Tween


func _ready() -> void:
	panel.pivot_offset = panel.size / 2.0
	close_button.pivot_offset = close_button.size / 2.0
	close_button.button_down.connect(_animate_close.bind(true))
	close_button.button_up.connect(_animate_close.bind(false))
	close_button.mouse_exited.connect(_animate_close.bind(false))
	chinese_button.pressed.connect(_on_language_pressed.bind("zh"))
	english_button.pressed.connect(_on_language_pressed.bind("en"))


func set_language(locale: String) -> void:
	chinese_button.set_pressed_no_signal(locale == "zh")
	english_button.set_pressed_no_signal(locale == "en")


func _on_language_pressed(locale: String) -> void:
	language_selected.emit(locale)


func open_settings(sound: bool, vibration: bool, supports_vibration: bool) -> void:
	title.text = "设置"
	options.show()
	message.hide()
	vibration_row.visible = supports_vibration
	sound_toggle.set_pressed_no_signal(sound)
	vibration_toggle.set_pressed_no_signal(vibration)
	_update_toggle(sound_toggle, sound, false)
	_update_toggle(vibration_toggle, vibration, false)
	_show_panel()


func open_notice(text: String) -> void:
	title.text = "提示"
	options.hide()
	message.text = text
	message.show()
	_show_panel()


func _show_panel() -> void:
	show()
	modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	close_button.scale = Vector2.ONE
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_open_tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	close_button.grab_focus()


func dismiss() -> void:
	if not visible:
		return
	feedback_requested.emit()
	_stop_tweens()
	close_button.release_focus()
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismiss()


func _on_sound_toggled(enabled: bool) -> void:
	_update_toggle(sound_toggle, enabled, true)
	sound_toggled.emit(enabled)
	feedback_requested.emit()


func _on_vibration_toggled(enabled: bool) -> void:
	_update_toggle(vibration_toggle, enabled, true)
	vibration_toggled.emit(enabled)
	feedback_requested.emit()


func _update_toggle(button: Button, enabled: bool, animate: bool) -> void:
	if _toggle_tweens.has(button):
		_toggle_tweens[button].kill()
	var knob: TextureRect = button.get_node("Knob")
	var track: NinePatchRect = button.get_node("On")
	var target_x := 159.0 if enabled else 9.0
	var target_alpha := 1.0 if enabled else 0.0
	if not animate:
		knob.position.x = target_x
		track.modulate.a = target_alpha
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(knob, "position:x", target_x, 0.1)
	tween.tween_property(track, "modulate:a", target_alpha, 0.1)
	_toggle_tweens[button] = tween


func _animate_close(pressed: bool) -> void:
	if not visible:
		return
	if _close_tween:
		_close_tween.kill()
	_close_tween = create_tween()
	_close_tween.tween_property(close_button, "scale", Vector2(0.9, 0.9) if pressed else Vector2.ONE, 0.08 if pressed else 0.12)


func _stop_tweens() -> void:
	if _open_tween:
		_open_tween.kill()
	if _close_tween:
		_close_tween.kill()
	for tween: Tween in _toggle_tweens.values():
		tween.kill()


func _exit_tree() -> void:
	_stop_tweens()
