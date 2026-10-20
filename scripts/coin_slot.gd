class_name CoinSlot
extends Control
const Ceramic = preload("res://scripts/ceramic_skin.gd")

signal pressed(index: int)

const Rules = preload("res://scripts/normal_game.gd")
const CoinVisual = preload("res://scripts/coin_visual.gd")
const Motion = preload("res://scripts/normal_motion.gd")
const FX = preload("res://scripts/normal_effects.gd")
const ROOT := Ceramic.SPRITES
const OPEN = preload(ROOT + "Texture/skin/BG_Trench.png")
const MERGE_HIGHLIGHT = preload(ROOT + "Texture/skin/BG_Trench_Merge.png")
const LOCKED = preload(ROOT + "Texture/skin/BG_Lock.png")
const UNLOCKABLE = preload(ROOT + "Texture/skin/BG_Lock2.png")
const UNLOCK_SHIMMER = preload("res://shaders/unlock_shimmer.gdshader")
const REWARD = preload(ROOT + "Texture/skin/BG_Lock_AD.png")
const LOCK_ICON = preload(ROOT + "ui/Icon_Lock.png")
const UNLOCK_ICON = preload(ROOT + "ui/Icon_Unlock.png")
const AD_ICON = preload(ROOT + "ui/Icon_ad_2.png")

var index := 0
var coin_views: Array[TextureRect] = []
var _base: TextureRect
var _icon: TextureRect
var _caption: Label
var _highlight: Panel
var _merge_highlight: TextureRect
var _unlock_shimmer: TextureRect
var _unlock_tween: Tween
var _selection_tween: Tween
var _guided := false
var _selected_count := 0
var _unlockable := false
var _merge_copy: TextureRect
var _merge_tween: Tween
var _merge_particles: Node2D
var _feedback: Tween
var _cover: Control
var _cover_clip: Control
var opening := false
var challenge := false


func _ready() -> void:
	custom_minimum_size = Vector2(122, 224)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	_base = _texture(OPEN, Vector2(4, 19), Vector2(114, 205))
	add_child(_base)
	_unlock_shimmer = _texture(UNLOCKABLE, _base.position, _base.size)
	_unlock_shimmer.name = "UnlockShimmer"
	var shimmer_material := ShaderMaterial.new()
	shimmer_material.shader = UNLOCK_SHIMMER
	shimmer_material.set_shader_parameter("streak_texture", preload(ROOT + "ui/LaserLight.png"))
	_unlock_shimmer.material = shimmer_material
	_unlock_shimmer.hide()
	add_child(_unlock_shimmer)
	_highlight = Panel.new()
	_highlight.position = Vector2(1, 12)
	_highlight.size = Vector2(120, 218)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 0.9, 0.25, 0.13)
	style.border_color = Color(1, 0.9, 0.25)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	_highlight.add_theme_stylebox_override("panel", style)
	_highlight.hide()
	add_child(_highlight)
	# 原版描边比槽底略大，保留外围光晕，避免挤压到硬币下方。
	_merge_highlight = _texture(MERGE_HIGHLIGHT, Vector2(-5, 9.5), Vector2(132, 222))
	_merge_highlight.name = "MergeHighlight"
	_merge_highlight.hide()
	add_child(_merge_highlight)
	_merge_copy = _texture(MERGE_HIGHLIGHT, _merge_highlight.position, _merge_highlight.size)
	_merge_copy.pivot_offset = _merge_copy.size / 2.0
	_merge_copy.hide()
	add_child(_merge_copy)
	_cover_clip = Control.new()
	_cover_clip.size = Vector2(122, 224)
	_cover_clip.clip_contents = true
	_cover_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover_clip)
	_cover = Control.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_clip.add_child(_cover)
	_base.reparent(_cover)
	_unlock_shimmer.reparent(_cover)
	_icon = _texture(LOCK_ICON, Vector2(35, 88), Vector2(52, 60))
	_icon.pivot_offset = _icon.size / 2.0
	_cover.add_child(_icon)
	_caption = Label.new()
	_caption.position = Vector2(0, 152)
	_caption.size = Vector2(122, 60)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 19)
	_caption.add_theme_color_override("font_color", Color("505050"))
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_caption)


static func _texture(texture: Texture2D, at: Vector2, dimensions: Vector2) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_SCALE
	result.position = at
	result.size = dimensions
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func skin_level(value: int) -> int:
	return posmod(value - 1, 15) + 1


static func make_coin(item: Dictionary, show_question: bool = false, war: bool = false) -> TextureRect:
	var visual := CoinVisual.new()
	visual.configure(item, show_question, war)
	return visual


static func coin_position(offset: int) -> Vector2:
	return Vector2(9.5, -7.1 + 19 * offset)


func render(cell: Dictionary, selected: int = 0, guided: bool = false, merge_ready: bool = false) -> void:
	_stop_selection()
	for view: TextureRect in coin_views:
		view.free()
	coin_views.clear()
	var state: int = cell.state
	_cover.position = Vector2.ZERO
	_cover.show()
	_guided = guided
	_selected_count = selected
	_unlockable = state == Rules.CellState.UNLOCKABLE
	z_index = 2 if selected > 0 else 0
	var open := state in [Rules.CellState.NORMAL, Rules.CellState.USING_AD]
	_base.texture = OPEN if open else (UNLOCKABLE if _unlockable else (REWARD if state == Rules.CellState.REWARD else LOCKED))
	_set_unlock_shimmer(_unlockable)
	_icon.visible = not open
	_icon.texture = UNLOCK_ICON if state == Rules.CellState.UNLOCKABLE else (AD_ICON if state == Rules.CellState.REWARD else LOCK_ICON)
	# 广告槽使用原版 70×44 横向图标，位置对应原预制体的 BG_AD1。
	_icon.position = Vector2(28, 138) if state == Rules.CellState.REWARD else Vector2(35, 88)
	_icon.size = Vector2(70, 44) if state == Rules.CellState.REWARD else Vector2(52, 60)
	_caption.text = "点击解锁" if state == Rules.CellState.UNLOCKABLE else ""
	_caption.visible = not _caption.text.is_empty()
	_highlight.visible = guided or selected > 0
	set_merge_ready(open and merge_ready)
	tooltip_text = "槽位 %d · %d/10" % [index + 1, cell.coins.size()] if open else (tr("奖励槽位") if state == Rules.CellState.REWARD else _caption.text)
	for offset in range(cell.coins.size()):
		var boundary: bool = cell.coins[offset].hidden and offset + 1 < cell.coins.size() and not cell.coins[offset + 1].hidden
		var view := make_coin(cell.coins[offset], boundary, challenge)
		view.position = coin_position(offset)
		add_child(view)
		coin_views.append(view)
	if selected > 0:
		select_coins(selected, false)


func select_coins(count: int, animate: bool = true) -> void:
	_stop_selection()
	_selected_count = count
	_highlight.visible = _guided or count > 0
	z_index = 2 if count > 0 else 0
	_selection_tween = create_tween().set_parallel(true)
	for offset in range(coin_views.size()):
		coin_views[offset].set_floating(offset >= coin_views.size() - count)
		var target := coin_position(offset)
		if offset >= coin_views.size() - count:
			target.y -= 35
		if animate:
			_selection_tween.tween_property(coin_views[offset], "position", target, 0.117).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			coin_views[offset].position = target
	if not animate or coin_views.is_empty():
		_selection_tween.kill()


func take_tail(count: int, parent: Node) -> Array[TextureRect]:
	_stop_selection()
	var moved: Array[TextureRect] = []
	for offset in range(coin_views.size() - count, coin_views.size()):
		var view := coin_views[offset]
		view.set_floating(false)
		view.reparent(parent)
		moved.append(view)
	coin_views.resize(coin_views.size() - count)
	return moved


func hide_tail(count: int) -> void:
	for offset in range(coin_views.size() - count, coin_views.size()):
		coin_views[offset].hide()


func set_guided(enabled: bool) -> void:
	_guided = enabled
	_highlight.visible = enabled or _selected_count > 0


func _set_unlock_shimmer(enabled: bool) -> void:
	if _unlock_shimmer.visible == enabled:
		return
	_unlock_shimmer.visible = enabled
	if _unlock_tween:
		_unlock_tween.kill()
	if not enabled:
		return
	# 原版 unlock1：0.75 秒斜向扫光，整个循环 2.5 秒。
	_unlock_tween = create_tween().set_loops().set_parallel(true)
	_unlock_tween.tween_callback(_unlock_shimmer.set_modulate.bind(Color(1, 1, 1, 40.0 / 255.0)))
	_unlock_tween.tween_method(_set_shimmer_offset, Vector2(-182.417, -119.181), Vector2(12.092, 26.163), 1.0 / 3.0)
	_unlock_tween.tween_method(_set_shimmer_offset, Vector2(12.092, 26.163), Vector2(167.699, 142.439), 5.0 / 12.0).set_delay(1.0 / 3.0)
	_unlock_tween.tween_property(_unlock_shimmer, "modulate:a", 0.0, 5.0 / 12.0).from(40.0 / 255.0).set_delay(1.0 / 6.0)
	_unlock_tween.tween_interval(2.5)


func _set_shimmer_offset(value: Vector2) -> void:
	_unlock_shimmer.material.set_shader_parameter("sweep_offset", value)


func _gui_input(event: InputEvent) -> void:
	var activated: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION
	activated = activated or (event is InputEventScreenTouch and event.index == 0 and event.pressed)
	activated = activated or (event.is_action_pressed("ui_accept") and not event.is_echo())
	if activated:
		accept_event()
		pressed.emit(index)


func _stop_selection() -> void:
	if _selection_tween:
		_selection_tween.kill()


func shake_selected() -> Tween:
	_stop_selection()
	var tween := create_tween().set_parallel(true)
	for offset in range(coin_views.size() - _selected_count, coin_views.size()):
		var view := coin_views[offset]
		view.set_floating(false)
		var origin := coin_position(offset)
		tween.tween_property(view, "position:y", origin.y, 0.117)
		for frame: Dictionary in [{"t": 0.0, "x": 0.0}, {"t": 0.0833, "x": -10.0}, {"t": 0.1667, "x": 10.0}, {"t": 0.25, "x": -10.0}]:
			var next_x: float = -10.0 if frame.t == 0.0 else (10.0 if frame.t < 0.1 else (-10.0 if frame.t < 0.2 else 0.0))
			tween.tween_property(view, "position:x", origin.x + next_x, 0.08333).from(origin.x + frame.x).set_delay(frame.t)
	_selected_count = 0
	_highlight.visible = _guided
	return tween


func lock_feedback() -> void:
	if _feedback and _feedback.is_running():
		return
	_feedback = Motion.play(self, "LockFeedback", {"": _icon})


func set_merge_ready(enabled: bool) -> void:
	if _merge_tween:
		_merge_tween.kill()
	if is_instance_valid(_merge_particles):
		_merge_particles.queue_free()
	_merge_highlight.visible = enabled
	_merge_highlight.modulate.a = 1.0
	_merge_highlight.scale = Vector2.ONE
	_merge_copy.visible = enabled
	_merge_copy.scale = Vector2.ONE
	if enabled:
		_merge_tween = Motion.play(self, "Merge", {"BG_Trench_Merge copy": _merge_copy})
		_merge_particles = FX.particles(self, Vector2(61, 112), "ready", true)


func reveal_coins(indices: Array, cell: Dictionary, tween: Tween) -> void:
	if indices.is_empty():
		return
	for offset: int in indices:
		coin_views[offset].reveal(tween, cell.coins[offset])
	var middle := (float(indices.front()) + float(indices.back())) / 2.0
	FX.particles(self, Vector2(60, 26 + middle * 19), "reveal")


func merge_into(level: int, tween: Tween) -> void:
	_stop_selection()
	for offset in range(coin_views.size()):
		coin_views[offset].set_floating(false)
		coin_views[offset].position = coin_position(offset)
	set_merge_ready(false)
	# Recycle one of the first eight every 1/32 s; retain the last two nodes.
	for step in range(8):
		tween.tween_callback(coin_views[step].hide).set_delay((step + 1) * 0.03125)
		for offset in range(step + 1, 10):
			tween.tween_property(coin_views[offset], "position:y", coin_position(offset - step - 1).y, 0.03125).from(coin_position(offset - step).y).set_delay(step * 0.03125)
	for offset in [8, 9]:
		coin_views[offset].reveal(tween, Rules.coin(level), 0.25)
	tween.tween_callback(FX.particles.bind(self, Vector2(60, 45), "reveal")).set_delay(0.25)
	tween.tween_interval(0.65)


func play_open(reward: bool) -> Tween:
	opening = true
	_set_unlock_shimmer(false)
	# The open trench remains underneath while the clipped lock cover slides out.
	var trench := _texture(OPEN, Vector2(4, 19), Vector2(114, 205))
	add_child(trench)
	move_child(trench, 0)
	var clip := "Adunlock" if reward else "unlock2"
	var tween := Motion.play(self, clip, {"adsLockBg": _cover, "Lock2": _cover, "Lock2/Icon_Lock": _icon}, {}, 1.0 if reward else 1.2)
	if not reward:
		var glow := Control.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)
		var light := _texture(MERGE_HIGHLIGHT, Vector2(-5, 9.5), Vector2(132, 222))
		light.pivot_offset = light.size / 2.0
		glow.add_child(light)
		var copy := light.duplicate()
		glow.add_child(copy)
		FX.particles(glow, Vector2(61, 112), "ready", true)
		var glow_tween := Motion.play(glow, "unlocklight", {"BG_Trench_Merge": light, "BG_Trench_Merge copy": copy}, {}, 1.2)
		glow_tween.finished.connect(glow.queue_free)
	tween.finished.connect(func():
		opening = false
		trench.queue_free())
	return tween


func _exit_tree() -> void:
	_stop_selection()
	if _unlock_tween:
		_unlock_tween.kill()
	for tween in [_merge_tween, _feedback]:
		if tween:
			tween.kill()
