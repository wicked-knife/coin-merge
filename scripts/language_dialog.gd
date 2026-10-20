extends Control
## A modal, keyboard-accessible language list inside the settings overlay.

signal selected(locale: String)
signal closed

const Languages = preload("res://scripts/localization.gd")
const Style = preload("res://scripts/dialog_style.gd")
var buttons: Dictionary = {}
var close_button: TextureButton
var scroll: ScrollContainer
var _current := Languages.DEFAULT
var _heading: Label
var _touch_active := false
var _touch_dragging := false
var _touch_start := Vector2.ZERO
var _scroll_start := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(preload("res://scripts/modal_shade.gd").new())
	var panel := Style.panel(Vector2(586, 1010))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -293
	panel.offset_right = 293
	panel.offset_top = -505
	panel.offset_bottom = 505
	add_child(panel)
	_heading = Label.new()
	_heading.text = "语言"
	_heading.position = Vector2(56, 26)
	_heading.size = Vector2(474, 70)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_heading)
	Style.title(_heading)
	close_button = Style.close_button(dismiss)
	close_button.position = Vector2(530, 28)
	panel.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(46, 132)
	scroll.size = Vector2(494, 824)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for item in Languages.LANGUAGES:
		var button := Button.new()
		button.name = item.locale
		button.text = item.name
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text_direction = Control.TEXT_DIRECTION_RTL if item.locale == "ar" else Control.TEXT_DIRECTION_LTR
		button.custom_minimum_size = Vector2(460, 76)
		button.toggle_mode = true
		Style.apply_button(button, "blue", 32)
		button.pressed.connect(func() -> void: selected.emit(item.locale))
		list.add_child(button)
		buttons[item.locale] = button
	var controls: Array[Control] = [close_button]
	for button: Button in buttons.values():
		controls.append(button)
	Style.focus_cycle(controls)
	hide()


func open(locale: String) -> void:
	_current = Languages.normalize(locale)
	for code: String in buttons:
		var button: Button = buttons[code]
		button.set_pressed_no_signal(code == _current)
		Style.apply_button(button, "yellow" if code == _current else "blue", 32)
	Style.title(_heading)
	show()
	var current: Control = buttons.get(_current, close_button)
	current.grab_focus()
	scroll.ensure_control_visible(current)


func dismiss() -> void:
	if visible:
		_touch_active = false
		_touch_dragging = false
		hide()
		closed.emit()


func _input(event: InputEvent) -> void:
	# Accept delivered touch gestures even when a desktop/web host does not
	# advertise a touchscreen to Godot's built-in ScrollContainer gesture code.
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_touch_active = scroll.get_global_rect().has_point(event.position)
			_touch_dragging = false
			_touch_start = scroll.get_global_transform_with_canvas().affine_inverse() * event.position
			_scroll_start = scroll.scroll_vertical
		else:
			if _touch_dragging:
				get_viewport().set_input_as_handled()
				scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
			_touch_active = false
			_touch_dragging = false
	elif event is InputEventScreenDrag and event.index == 0 and _touch_active:
		var at: Vector2 = scroll.get_global_transform_with_canvas().affine_inverse() * event.position
		if not _touch_dragging and at.distance_to(_touch_start) > 12:
			_touch_dragging = true
			scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		if _touch_dragging:
			scroll.scroll_vertical = _scroll_start - roundi(at.y - _touch_start.y)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		Style.title(_heading)
		_heading.text_direction = Languages.text_direction()
