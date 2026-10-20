extends Node2D
const Ceramic = preload("res://scripts/ceramic_skin.gd")
const ROOT := Ceramic.SPRITES
## Cocos gravity emitter port: per-particle lifespan/size/color variation and rate.
## Keeping this simulation avoids losing Cocos' >100% lifespan variation in Godot.
var config: Dictionary
var texture: Texture2D
var continuous := false
var _particles: Array[Dictionary] = []
var _elapsed := 0.0
var _accumulator := 0.0
var _gravity := Vector2.ZERO


func configure(data: Dictionary, loop: bool) -> void:
	config = data
	continuous = loop
	texture = load(ROOT + config.texture)
	var g: Array = config.get("gravity", [0, 0, 0])
	_gravity = Vector2(g[1], -g[2])
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if config.get("_dstBlendFactor", 771) == 1 else CanvasItemMaterial.BLEND_MODE_MIX
	material = blend


func _random(field: String, default: float = 0.0) -> float:
	return float(config.get(field, default)) + randf_range(-1, 1) * float(config.get(field + "Var", 0.0))


func _color(field: String) -> Color:
	var packed: int = config.get(field, [4, 4294967295])[1]
	var variance: int = config.get(field + "Var", [4, 0])[1]
	var channels: Array[float] = []
	for shift in [0, 8, 16, 24]:
		channels.append(clampf(float((packed >> shift) & 255) / 255.0 + randf_range(-1, 1) * float((variance >> shift) & 255) / 255.0, 0, 1))
	return Color(channels[0], channels[1], channels[2], channels[3])


func _emit() -> void:
	var life := maxf(0.0, _random("life", 1.0))
	if life == 0:
		return
	var variance: Array = config.get("posVar", [0, 0, 0])
	var direction := -deg_to_rad(_random("angle"))
	_particles.append({"age": 0.0, "life": life,
		"position": Vector2(randf_range(-1, 1) * variance[1], randf_range(-1, 1) * variance[2]),
		"velocity": Vector2.from_angle(direction) * _random("speed"),
		"radial": _random("radialAccel"), "tangent": -_random("tangentialAccel"),
		"size_start": maxf(0, _random("startSize", 10)), "size_end": maxf(0, _random("endSize", 10)),
		"rotation_start": -deg_to_rad(_random("startSpin")), "rotation_end": -deg_to_rad(_random("endSpin")),
		"color_start": _color("_startColor"), "color_end": _color("_endColor")})


func _process(delta: float) -> void:
	# Small substeps preserve radial/tangential motion under a low frame rate.
	var remaining := minf(delta, 0.1)
	while remaining > 0:
		var dt := minf(remaining, 1.0 / 120.0)
		remaining -= dt
		var duration: float = config.get("duration", -1.0)
		if continuous or duration < 0 or _elapsed < duration:
			_accumulator += dt * float(config.get("emissionRate", 10))
			while _accumulator >= 1:
				_accumulator -= 1
				if _particles.size() < int(config.get("totalParticles", 150)):
					_emit()
		_elapsed += dt
		for index in range(_particles.size() - 1, -1, -1):
			var p := _particles[index]
			p.age += dt
			if p.age >= p.life:
				_particles.remove_at(index)
				continue
			var radial: Vector2 = p.position.normalized()
			var tangent := Vector2(-radial.y, radial.x)
			p.velocity += (_gravity + radial * p.radial + tangent * p.tangent) * dt
			p.position += p.velocity * dt
	queue_redraw()
	if not continuous and _elapsed > float(config.get("duration", 0.1)) and _particles.is_empty():
		queue_free()


func _draw() -> void:
	for p: Dictionary in _particles:
		var ratio: float = p.age / p.life
		var extent: float = lerpf(p.size_start, p.size_end, ratio)
		var rotation_angle: float = lerpf(p.rotation_start, p.rotation_end, ratio)
		draw_set_transform(p.position, rotation_angle)
		draw_texture_rect(texture, Rect2(Vector2.ONE * -extent / 2.0, Vector2.ONE * extent), false, p.color_start.lerp(p.color_end, ratio))
	draw_set_transform(Vector2.ZERO)
