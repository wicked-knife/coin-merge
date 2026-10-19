extends RefCounted
## Play captured Cocos keyframes on explicitly mapped Godot nodes.
const Data = preload("res://scripts/normal_motion_data.gd")


static func play(owner: Node, clip_name: String, bindings: Dictionary, origins: Dictionary = {}, speed: float = 1.0, loops: int = -1) -> Tween:
	var clip: Dictionary = Data.CLIPS[clip_name]
	var tween := owner.create_tween().set_parallel(true)
	if (clip.loop if loops == -1 else loops == 1) and clip.duration > 0:
		tween.set_loops()
	for track: String in clip.tracks:
		var split := track.split("|")
		var path := split[0]
		if not bindings.has(path) or not is_instance_valid(bindings[path]):
			continue
		var node: Node = bindings[path]
		var prop := split[1]
		var property := _property(prop)
		if property.is_empty():
			continue
		var frames: Array = clip.tracks[track]
		var origin: Vector2 = origins.get(path, Vector2.ZERO)
		node.set_indexed(property, _value(prop, frames[0].value, origin))
		for index in range(1, frames.size()):
			var previous: Dictionary = frames[index - 1]
			var current: Dictionary = frames[index]
			var duration: float = (current.frame - previous.frame) / speed
			if prop == "active":
				tween.tween_callback(node.set_indexed.bind(property, current.value)).set_delay(current.frame / speed)
			else:
				var segment := tween.tween_property(node, property, _value(prop, current.value, origin), maxf(0.0001, duration)).from(_value(prop, previous.value, origin)).set_delay(previous.frame / speed)
				match previous.get("curve", ""):
					"quadOut": segment.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					"quadIn": segment.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					"sineOut": segment.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
					"backOut": segment.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Keep clip timing even for static tracks, delayed first frames, or absent old nodes.
	tween.tween_interval(maxf(0.001, clip.duration / speed))
	return tween


static func _property(prop: String) -> NodePath:
	return NodePath({"x": "position:x", "y": "position:y", "position": "position", "angle": "rotation_degrees", "scale": "scale", "opacity": "modulate:a", "active": "visible"}.get(prop, ""))


static func _value(prop: String, value: Variant, origin: Vector2) -> Variant:
	match prop:
		"x": return origin.x + float(value)
		"y": return origin.y - float(value)
		"position": return origin + Vector2(value[0], -value[1])
		"scale": return Vector2(value[0], value[1])
		"angle": return -float(value)
		"opacity": return float(value) / 255.0
	return value


static func finish_or_exit(tween: Tween, owner: Node) -> bool:
	# Killing a bound Tween does not emit finished. Resume helper coroutines when
	# their scene leaves as well, so their captured textures/materials are released.
	if not owner.is_inside_tree():
		return false
	var state := {"exited": false}
	var cancel := func():
		state.exited = true
		tween.kill()
		tween.finished.emit()
	owner.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
	await tween.finished
	if is_instance_valid(owner) and owner.tree_exiting.is_connected(cancel):
		owner.tree_exiting.disconnect(cancel)
	return not state.exited
