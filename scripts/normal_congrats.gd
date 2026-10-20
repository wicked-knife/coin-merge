extends Control
const Ceramic = preload("res://scripts/ceramic_skin.gd")
signal dismissed
const FX = preload("res://scripts/normal_effects.gd")
var _tween: Tween
var _closing := false


func _ready() -> void:
	size = Vector2(750, 1334)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func open(value: int, final: bool) -> void:
	for child in get_children():
		child.queue_free()
	_closing = false
	modulate.a = 1
	show()
	var shade := preload("res://scripts/modal_shade.gd").new()
	add_child(shade)
	# This celebration dismisses on any tap, so its shade passes input to the parent.
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text("normal.congrats", 507, 48, Color.WHITE)
	var coin := FX.big_coin(self, value, Vector2(120, 120))
	coin.get_child(0).add_theme_font_size_override("font_size", 40)
	coin.position = Vector2(315, 597)
	coin.scale = Vector2.ZERO
	_text("normal.level_clear" if final else "normal.level_up", 697, 30, Color("ffdc64"))
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2).from(0.0)
	_tween.tween_property(coin, "scale", Vector2.ONE, 0.3).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _text(message: String, y: float, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.position = Vector2(20, y)
	label.size = Vector2(710, 100)
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_size == 48:
		label.add_theme_font_override("font", Ceramic.FONT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func close() -> void:
	if _closing:
		return
	_closing = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.15)
	_tween.tween_callback(func():
		hide()
		dismissed.emit())


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.index == 0 and event.pressed) or event.is_action_pressed("ui_accept"):
		accept_event()
		close()
