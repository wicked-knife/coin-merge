extends TextureRect

const ROOT := "res://assets/rea_original/sprites/"
const NUMBERS = preload("res://assets/rea_original/fonts/number01/number01.fnt")
const Motion = preload("res://scripts/normal_motion.gd")
var item := {"level": 1, "hidden": false}
var content: Control
var icon: TextureRect
var number: Label
var question: TextureRect
var _float: Tween


func configure(data: Dictionary, show_question: bool = false) -> void:
	item = data.duplicate()
	if content == null:
		size = Vector2(101, 67)
		pivot_offset = size / 2.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		content = Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(content)
		icon = TextureRect.new()
		icon.size = size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		number = Label.new()
		number.position = Vector2(0.5, 24.5)
		number.size = Vector2(100, 60)
		number.scale.y = 0.6
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		number.add_theme_font_override("font", NUMBERS)
		number.add_theme_color_override("font_shadow_color", Color(0.42, 0.22, 0.03, 0.4))
		number.add_theme_constant_override("shadow_offset_y", 2)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(number)
		question = TextureRect.new()
		question.texture = preload(ROOT + "Texture/skin/Icon_QuestionMark.png")
		question.position = Vector2(35, 21)
		question.size = Vector2(31, 32)
		question.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		question.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(question)
	icon.texture = load(ROOT + "Texture/skin/normal/%d.png" % (16 if item.hidden else posmod(item.level - 1, 15) + 1))
	number.text = str(item.level)
	number.add_theme_font_size_override("font_size", 32 if item.level < 100 else 26)
	number.visible = not item.hidden
	question.visible = item.hidden and show_question


func set_floating(enabled: bool) -> void:
	if _float:
		_float.kill()
	content.position = Vector2.ZERO
	if enabled:
		# The same captured 10 px float applies to the face and number together.
		_float = Motion.play(self, "War_Select", {"icon": content})


func reveal(tween: Tween, data: Dictionary, delay: float = 0.0) -> void:
	question.hide()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15).set_delay(delay)
	tween.tween_callback(configure.bind(data, false)).set_delay(delay + 0.15)
	tween.tween_property(self, "scale", Vector2.ONE, 0.15).from(Vector2.ZERO).set_delay(delay + 0.15)


func _exit_tree() -> void:
	if _float:
		_float.kill()
