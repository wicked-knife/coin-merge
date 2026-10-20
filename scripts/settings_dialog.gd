extends Control

const DialogStyle = preload("res://scripts/dialog_style.gd")
const Languages = preload("res://scripts/localization.gd")
const ACTION_FONT_SIZE := 36

signal closed
signal sound_toggled(enabled: bool)
signal vibration_toggled(enabled: bool)
signal language_selected(locale: String)
signal feedback_requested
signal home_requested
signal retry_requested

@onready var panel: NinePatchRect = $Panel
@onready var title: Label = $Panel/Title
@onready var close_button: TextureButton = $Panel/CloseButton
@onready var options: VBoxContainer = $Panel/Options
@onready var sound_toggle: Button = $Panel/Options/SoundRow/Toggle
@onready var vibration_row: HBoxContainer = $Panel/Options/VibrationRow
@onready var vibration_toggle: Button = $Panel/Options/VibrationRow/Toggle
@onready var language_button: Button = $Panel/Options/LanguageRow/CurrentLanguage
@onready var message: Label = $Panel/Message
@onready var game_actions: VBoxContainer = $Panel/GameActions
@onready var home_button: Button = $Panel/GameActions/HomeButton
@onready var retry_button: Button = $Panel/GameActions/RetryButton

# 游戏实例使用更高的面板，为选项和两枚操作按钮留出间距。
@export var in_game_layout := false

var _open_tween: Tween
var _toggle_tweens: Dictionary = {}
var _close_tween: Tween
var _home_pending := false
var language_dialog: Control


func _ready() -> void:
	DialogStyle.title(title)
	DialogStyle.apply_button(home_button, "yellow", ACTION_FONT_SIZE)
	DialogStyle.apply_button(retry_button, "blue", ACTION_FONT_SIZE)
	panel.pivot_offset = panel.size / 2.0
	close_button.pivot_offset = close_button.size / 2.0
	close_button.button_down.connect(_animate_close.bind(true))
	close_button.button_up.connect(_animate_close.bind(false))
	close_button.mouse_exited.connect(_animate_close.bind(false))
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	language_dialog = preload("res://scripts/language_dialog.gd").new()
	language_dialog.name = "LanguageDialog"
	add_child(language_dialog)
	language_dialog.selected.connect(_on_language_pressed)
	language_dialog.closed.connect(_close_language_picker)
	language_button.pressed.connect(open_language_picker)
	DialogStyle.apply_button(language_button, "blue", 26)
	_set_game_layout(in_game_layout)
	retry_button.pressed.connect(_on_retry_pressed)


func set_language(locale: String) -> void:
	language_button.text = Languages.native_name(locale)
	language_button.text_direction = Control.TEXT_DIRECTION_RTL if Languages.normalize(locale) == "ar" else Control.TEXT_DIRECTION_LTR
	DialogStyle.fit_button_text(language_button, 26)
	DialogStyle.fit_button_text(home_button, ACTION_FONT_SIZE)
	DialogStyle.fit_button_text(retry_button, ACTION_FONT_SIZE)


func _on_language_pressed(locale: String) -> void:
	language_selected.emit(locale)
	set_language(TranslationServer.get_locale())
	language_dialog.dismiss()


func open_language_picker() -> void:
	if not visible:
		return
	feedback_requested.emit()
	panel.hide()
	language_dialog.open(TranslationServer.get_locale())


func _close_language_picker() -> void:
	panel.show()
	language_button.grab_focus()


func open_settings(sound: bool, vibration: bool, supports_vibration: bool, in_game: bool = false) -> void:
	_set_game_layout(in_game)
	_home_pending = false
	home_button.disabled = false
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
	_set_game_layout(false)
	title.text = "提示"
	options.hide()
	message.text = text
	message.show()
	_show_panel()


func _show_panel() -> void:
	_stop_tweens()
	# Control hit testing follows sibling order, regardless of visual z_index.
	# Challenge boards are created after this dialog and would intercept its clicks.
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	show()
	panel.show()
	language_dialog.hide()
	DialogStyle.refresh_text(self)
	set_language(TranslationServer.get_locale())
	_layout_game_actions()
	modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	close_button.scale = Vector2.ONE
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_open_tween.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_set_focus_cycle()
	close_button.grab_focus()


func _set_game_layout(in_game: bool) -> void:
	var half_height := 390.0 if in_game else 297.5
	panel.offset_top = -half_height
	panel.offset_bottom = half_height
	panel.pivot_offset = panel.size / 2.0
	options.add_theme_constant_override("separation", 20 if in_game else 42)
	game_actions.visible = in_game


func _layout_game_actions() -> void:
	if not game_actions.visible:
		return
	# Resolve the action area after fonts and the taller panel are in place.
	# Explicit top offsets also keep Web's initial container sizing inside the card.
	var height := game_actions.get_combined_minimum_size().y
	game_actions.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	game_actions.offset_left = 45.0
	game_actions.offset_right = -45.0
	game_actions.offset_top = panel.size.y - 64.0 - height
	game_actions.offset_bottom = panel.size.y - 64.0


# 显式环绕弹窗内可用控件，键盘焦点不会落到后面的主界面。
func _set_focus_cycle() -> void:
	var buttons: Array[Control] = [close_button]
	if options.visible:
		buttons.append(sound_toggle)
		if vibration_row.visible:
			buttons.append(vibration_toggle)
		buttons.append(language_button)
	if game_actions.visible:
		buttons.append(home_button)
		buttons.append(retry_button)
	DialogStyle.focus_cycle(buttons)


func _on_home_pressed() -> void:
	if not visible or not game_actions.visible or _home_pending:
		return
	_home_pending = true
	home_button.disabled = true
	home_requested.emit()


func _on_retry_pressed() -> void:
	if not visible or not game_actions.visible or _home_pending:
		return
	feedback_requested.emit()
	retry_requested.emit()


func dismiss() -> void:
	if not visible:
		return
	feedback_requested.emit()
	_stop_tweens()
	language_dialog.hide()
	panel.show()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if language_dialog.visible:
			language_dialog.dismiss()
		else:
			dismiss()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		DialogStyle.refresh_text(panel)
		set_language(TranslationServer.get_locale())


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
