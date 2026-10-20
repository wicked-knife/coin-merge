extends Control
const Ceramic = preload("res://scripts/ceramic_skin.gd")
signal activated(step: int)
const Motion = preload("res://scripts/normal_motion.gd")
const ROOT := Ceramic.UI
var hand: TextureRect
var bubble: PanelContainer
var label: Label
var _shade: ColorRect
var _hole := Rect2()
var _step := -1
var _hand_tween: Tween


func _ready() -> void:
	size = Vector2(750, 1334)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.size = size
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/tutorial_mask.gdshader")
	_shade.material = mat
	add_child(_shade)
	bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 0.667, 0, 0.9)
	style.set_corner_radius_all(12)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)
	add_child(bubble)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 24)
	label.custom_minimum_size.x = 120
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)
	hand = TextureRect.new()
	hand.texture = preload(ROOT + "Guide_Hand.png")
	hand.size = Vector2(88, 104)
	hand.pivot_offset = Vector2(10, 10)
	hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hand)
	hide()


func focus(step: int, rect: Rect2, message: String, active: bool) -> void:
	visible = active and step >= 0 and step not in [2, 8]
	if not visible:
		return
	_step = step
	_hole = Rect2(rect.position - global_position, rect.size)
	_shade.material.set_shader_parameter("hole_rect", Vector4(_hole.position.x / size.x, _hole.position.y / size.y, _hole.size.x / size.x, _hole.size.y / size.y))
	var mask: Texture2D = load(ROOT + ("Guide_Mask3.png" if step in [3, 10] else ("Guide_Mask2.png" if step == 9 else "Guide_Mask1.png")))
	_shade.material.set_shader_parameter("hole_mask", mask)
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 360
	bubble.size.x = 390
	bubble.visible = step not in [5, 6, 7, 10]
	_refresh_bubble()
	hand.visible = step != 9
	hand.position = _hole.get_center() + Vector2(20, 12)
	if _hand_tween:
		_hand_tween.kill()
	_hand_tween = Motion.play(self, "GuideHand", {"": hand})


func _refresh_bubble() -> void:
	bubble.reset_size()
	bubble.position = Vector2(clampf(_hole.get_center().x - bubble.size.x / 2.0, 15, size.x - bubble.size.x - 15), _hole.position.y - bubble.size.y - 25)
	if _step == 9:
		bubble.position.y = _hole.end.y + 35
		bubble.position.x = clampf(_hole.get_center().x - bubble.size.x + 30, 15, size.x - bubble.size.x - 15)
	label.text_direction = preload("res://scripts/localization.gd").text_direction()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		call_deferred("_refresh_bubble")


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION
	pressed = pressed or (event is InputEventScreenTouch and event.index == 0 and event.pressed)
	pressed = pressed or event.is_action_pressed("ui_accept")
	if pressed:
		accept_event()
		if _step == 9 or (event is InputEventMouse and _hole.has_point(event.position)) or (event is InputEventScreenTouch and _hole.has_point(event.position)) or event is InputEventKey:
			activated.emit(_step)


func _exit_tree() -> void:
	if _hand_tween:
		_hand_tween.kill()
