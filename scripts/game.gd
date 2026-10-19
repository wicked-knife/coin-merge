extends Control

@onready var home_button: TextureButton = $HomeButton
@onready var click_sound: AudioStreamPlayer = $ClickSound

var _leaving := false
var _button_tween: Tween
var _return_tween: Tween


func _ready() -> void:
	home_button.pivot_offset = home_button.size / 2.0
	home_button.button_down.connect(_animate_home_button.bind(true))
	home_button.button_up.connect(_animate_home_button.bind(false))
	home_button.mouse_exited.connect(_animate_home_button.bind(false))


func _animate_home_button(pressed: bool) -> void:
	if _leaving:
		return
	if _button_tween:
		_button_tween.kill()
	_button_tween = create_tween()
	var target := Vector2(0.9, 0.9) if pressed else Vector2.ONE
	_button_tween.tween_property(home_button, "scale", target, 0.08 if pressed else 0.12)


func _on_home_button_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	home_button.disabled = true
	# 沿用主界面的静音状态，留出点击音效的播放时间。
	click_sound.play()
	_return_tween = create_tween()
	_return_tween.tween_interval(0.15)
	_return_tween.tween_callback(_return_to_main_menu)


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		_leaving = false
		home_button.disabled = false
		push_error("无法返回主界面：%s" % error_string(error))


func _exit_tree() -> void:
	if _button_tween:
		_button_tween.kill()
	if _return_tween:
		_return_tween.kill()
