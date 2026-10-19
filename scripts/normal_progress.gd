extends RefCounted
const Motion = preload("res://scripts/normal_motion.gd")
const Slot = preload("res://scripts/coin_slot.gd")
const ROOT := "res://assets/rea_original/sprites/"
const NUMBERS = preload("res://assets/rea_original/fonts/number01/number01.fnt")
const NAMES := ["Target5", "Target6", "Target7", "Target9", "Target10"]
var targets: Array[Control] = []
var host: Control
var _tweens: Array[Tween] = []
var current := -1
var values: Array = []


func setup(parent: Control) -> void:
	host = parent
	for name: String in NAMES:
		var old := host.get_node(name)
		host.remove_child(old)
		old.queue_free()
	for index in range(5):
		var target := Control.new()
		target.name = NAMES[index]
		target.position = Vector2(4 + 96 * index, 14)
		target.size = Vector2(56, 56)
		target.pivot_offset = target.size / 2.0
		target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(target)
		targets.append(target)
		if index == 4:
			_tex(target, "SunRays", "ui/TargetBG_4.png", Vector2(-28.5, -28), Vector2(113, 112))
		_tex(target, "Gray", "Texture/skin/TargetBG_1.png" if index < 4 else "ui/TargetBG_4_b515ca35.png", Vector2.ZERO, Vector2(56, 56))
		var next := Control.new()
		next.name = "Next"
		next.size = Vector2(56, 56)
		next.pivot_offset = next.size / 2.0
		next.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(next)
		_tex(next, "CurrentRing", "Texture/skin/TargetBG_2.png", Vector2(-8, -9), Vector2(72, 74))
		_tex(next, "Coin", "Texture/skin/big/BigCoin5.png", Vector2.ZERO, Vector2(56, 56))
		_tex(target, "Over", "Texture/skin/TargetBG_5.png", Vector2.ZERO, Vector2(56, 56))
		var label := Label.new()
		label.name = "Number"
		label.size = Vector2(56, 56)
		label.pivot_offset = label.size / 2.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", NUMBERS)
		label.add_theme_font_size_override("font_size", 32)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(label)
		if index == 4:
			_tex(target, "Crown", "ui/TargetBG_4_d27bfba7.png", Vector2(-5, -51), Vector2(66, 60))


func _tex(parent: Control, name: String, path: String, at: Vector2, dimensions: Vector2) -> void:
	var view := Slot._texture(load(ROOT + path), at, dimensions)
	view.name = name
	view.pivot_offset = view.size / 2.0
	parent.add_child(view)


func refresh(numbers: Array, stage: int, force: bool = false) -> void:
	if current == stage and values == numbers and not force:
		return
	stop()
	current = stage
	values = numbers.duplicate()
	for index in range(5):
		var target := targets[index]
		target.scale = Vector2.ONE
		var label: Label = target.get_node("Number")
		label.text = str(numbers[index])
		label.scale = Vector2.ONE
		label.modulate.a = 0 if index < stage else 1
		target.get_node("Next/Coin").texture = load(ROOT + "Texture/skin/big/BigCoin%d.png" % Slot.skin_level(numbers[index]))
		var next: Control = target.get_node("Next")
		next.scale = Vector2.ONE
		next.visible = index == stage
		next.modulate.a = 1
		target.get_node("Over").modulate.a = 1 if index < stage else 0
		if index == stage:
			_tweens.append(_play(index, "Progress_FinalTargeStandby" if index == 4 else "Progress_TargetStandby"))
		elif index == 4:
			_tweens.append(_play(index, "Progress_TargetStandbyNormal"))


func advance(previous: int, final: bool = false) -> bool:
	stop()
	var finished := _play(previous, "Progress_FinalTargeFinished" if final else "Progress_TargetFinshed")
	if not await Motion.finish_or_exit(finished, host):
		return false
	if final:
		current = 5
		return true
	var next := previous + 1
	targets[next].get_node("Next").show()
	# Future targets have no completion mark during their change clip.
	var bindings := _bindings(next)
	bindings.erase("over")
	var change := Motion.play(host, "Progress_FinalTargeBegin" if next == 4 else "Progress_TargetChange", bindings, _origins(next))
	if not await Motion.finish_or_exit(change, host):
		return false
	refresh(values, next, true)
	return true


func _bindings(index: int) -> Dictionary:
	var t := targets[index]
	var result := {"": t, "next": t.get_node("Next"), "over": t.get_node("Over"), "label": t.get_node("Number")}
	if index == 4:
		result.merge({"TargetBG_4": t.get_node("SunRays"), "TargetBG_4.2": t.get_node("Crown"), "TargetBG_4.1": t.get_node("Gray")})
	return result


func _origins(index: int) -> Dictionary:
	return {"TargetBG_4.2": Vector2(-5, 7)} if index == 4 else {}


func _play(index: int, clip: String) -> Tween:
	var tween := Motion.play(host, clip, _bindings(index), _origins(index))
	_tweens.append(tween)
	return tween


func stop() -> void:
	for tween in _tweens:
		if tween:
			tween.kill()
	_tweens.clear()
