extends RefCounted
## Native Godot emitters using the captured textures and motion parameters.
const ROOT := "res://assets/rea_original/sprites/"
const ParticleView = preload("res://scripts/normal_particles.gd")
const ParticleData = preload("res://scripts/normal_particle_data.gd")
const Motion = preload("res://scripts/normal_motion.gd")
const NUMBERS = preload("res://assets/rea_original/fonts/number01/number01.fnt")


static func particles(parent: Node, at: Vector2, kind: String = "reveal", continuous: bool = false, variant: int = 0) -> Node2D:
	var emitter := ParticleView.new()
	emitter.name = "Particles_" + kind
	emitter.configure(ParticleData.EMITTERS[kind][variant], continuous)
	parent.add_child(emitter)
	emitter.position = at
	return emitter


static func combo(parent: Control, count: int) -> void:
	var label := Label.new()
	label.name = "Combo"
	label.size = Vector2(650, 100)
	label.position = Vector2(50, 510)
	label.pivot_offset = label.size / 2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = TranslationServer.translate("normal.combo_%d" % mini(count, 9))
	label.add_theme_font_size_override("font_size", 60 + 4 * mini(count - 2, 6))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Arial"])
	font.font_weight = 700
	font.font_italic = true
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", Color("ffc832"))
	label.add_theme_color_override("font_outline_color", Color("c86400"))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	particles(label, label.size / 2.0, "combo")
	var tween := Motion.play(label, "Combo", {"Combo1": label})
	tween.finished.connect(label.queue_free)


static func big_coin(parent: Node, value: int, dimensions: Vector2 = Vector2(200, 200)) -> TextureRect:
	var coin := TextureRect.new()
	coin.texture = load(ROOT + "Texture/skin/big/BigCoin%d.png" % (posmod(value - 1, 15) + 1))
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.size = dimensions
	coin.pivot_offset = coin.size / 2.0
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(coin)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = str(value)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", NUMBERS)
	label.add_theme_font_size_override("font_size", int(dimensions.x * 0.5))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.add_child(label)
	return coin


static func fly_to_target(parent: Control, value: int, destination: Vector2) -> bool:
	var coin := big_coin(parent, value, Vector2(160, 166))
	coin.name = "FinalBigCoin"
	var start := Vector2(295, 584)
	coin.position = start
	particles(coin, coin.size / 2.0, "bigcoin")
	var streak := TextureRect.new()
	streak.texture = coin.texture
	streak.size = coin.size
	streak.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/unlock_shimmer.gdshader")
	shader_material.set_shader_parameter("streak_texture", preload(ROOT + "ui/LaserLight.png"))
	streak.material = shader_material
	coin.add_child(streak)
	var sweep := coin.create_tween()
	sweep.tween_interval(0.6667)
	sweep.tween_method(func(v: Vector2): shader_material.set_shader_parameter("sweep_offset", v), Vector2(-182.417, -119.181), Vector2(167.699, 142.439), 0.7167)
	var appear := Motion.play(coin, "Bigcoin_Appear", {"": coin}, {"": start})
	if not await Motion.finish_or_exit(appear, coin):
		return false
	var from := coin.global_position
	var to := destination - coin.size / 2.0
	var c1 := parent.global_position + Vector2(475, 567) - coin.size / 2.0
	var c2 := parent.global_position + Vector2(575, 167) - coin.size / 2.0
	var flight := coin.create_tween().set_parallel(true)
	flight.tween_method(func(t: float): coin.global_position = from.bezier_interpolate(c1, c2, to, t), 0.0, 1.0, 0.7)
	flight.tween_property(coin, "scale", Vector2(0.365, 0.365), 0.7)
	flight.tween_property(coin, "modulate:a", 100.0 / 255.0, 0.7)
	if not await Motion.finish_or_exit(flight, coin):
		return false
	coin.queue_free()
	return true


static func fireworks(parent: Control) -> void:
	var layer := Control.new()
	layer.name = "Fireworks"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	var sequence := layer.create_tween()
	for index in range(randi_range(4, 6)):
		sequence.tween_callback(_firework_burst.bind(layer, index))
		sequence.tween_interval(0.62)
	sequence.tween_interval(0.55)
	sequence.tween_callback(layer.queue_free)


static func _firework_burst(parent: Control, index: int) -> void:
	particles(parent, Vector2(randf_range(185, 565), randf_range(333, 1000)), "firework", false, index % 2)
