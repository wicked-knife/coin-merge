extends Control
## Coordinates from the published war-cell-item prefab.

signal pressed(index: int)
const CoinVisual = preload("res://scripts/coin_visual.gd")
const FX = preload("res://scripts/normal_effects.gd")
const ParticleView = preload("res://scripts/normal_particles.gd")
const ROOT := "res://assets/rea_original/sprites/"
const COIN_ORIGIN := Vector2(54, -39)
const COLORS := [Color.WHITE, Color("ffee5f"), Color("fd736d"), Color("ffb7a2"),
	Color("64a4fd"), Color("7deaf5"), Color("8d61e9"), Color("d0f37f"),
	Color("ffac56"), Color("cb9770"), Color("5bbb57"), Color("5a87e6")]
# 0f06036bd.json, prefab 5, Light_Warcoin ParticleSystem (node 16).
const WAR_PARTICLES := {"texture": "ui/Light1.png", "_dstBlendFactor": 1,
	"totalParticles": 500, "duration": 0.1, "emissionRate": 500, "life": 0.3,
	"lifeVar": 0.5, "angle": -175, "angleVar": 180, "speed": 180, "startSize": 12,
	"startSizeVar": 10, "endSize": 12, "endSizeVar": 10, "startSpin": 30,
	"tangentialAccel": 100, "tangentialAccelVar": -100, "radialAccel": -100,
	"radialAccelVar": 100, "_startColor": [4, 2740373706],
	"_startColorVar": [4, 3333292005], "_endColor": [4, 3591610797],
	"_endColorVar": [4, 3170498923], "posVar": [0, 20, 90], "gravity": [0, 20, 80]}
var index := 0
var coin_views: Array[TextureRect] = []
var coin_parent: Control
var arrow: TextureRect
var tick: TextureRect
var _mask: TextureRect
var _light: Control
var _selected_count := 0
var _selection_tween: Tween
var _light_tween: Tween


func _ready() -> void:
	size = Vector2(110, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	add_child(_texture(preload(ROOT + "Texture/skin/BG_Trench.png"), Vector2.ZERO, size))
	coin_parent = Control.new()
	coin_parent.name = "CoinParent"
	coin_parent.position = COIN_ORIGIN
	coin_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coin_parent)
	_mask = _texture(preload(ROOT + "Texture/skin/Bg_Mask.png"), Vector2(0, 200), Vector2(110, 32))
	_mask.z_index = 12
	_mask.z_as_relative = false
	add_child(_mask)
	arrow = _texture(preload(ROOT + "Texture/skin/ColorArrow.png"), Vector2(39, 7.002), Vector2(32, 21))
	_mask.add_child(arrow)
	tick = _texture(preload(ROOT + "Texture/skin/Tick.png"), Vector2(18.5, 62.5), Vector2(73, 57))
	tick.z_index = 13
	add_child(tick)
	tick.hide()
	_light = Control.new()
	_light.name = "WarCoinLight"
	_light.position = Vector2(55, 90)
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_light)
	_light.hide()


static func _texture(image: Texture2D, at: Vector2, dimensions: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture = image
	view.position = at
	view.size = dimensions
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


static func coin_position(offset: int) -> Vector2:
	# Cocos coin center (0, -48 - 19*i), translated to a top-left Godot rect.
	return Vector2(-50.5, 14.5 + 19 * offset)


func render(cell: Dictionary) -> void:
	_stop_selection()
	for view in coin_views:
		view.free()
	coin_views.clear()
	_selected_count = 0
	z_index = 0
	for offset in range(cell.coins.size()):
		var view := CoinVisual.new()
		var question: bool = cell.coins[offset].hidden and offset + 1 < cell.coins.size() and not cell.coins[offset + 1].hidden
		view.configure(cell.coins[offset], question, true)
		view.position = coin_position(offset)
		coin_parent.add_child(view)
		coin_views.append(view)
	var complete: bool = cell.target > 0 and cell.coins.size() == 10
	for item: Dictionary in cell.coins:
		complete = complete and not item.hidden and item.level == cell.target
	arrow.visible = cell.target > 0 and not complete
	if cell.target > 0:
		arrow.modulate = COLORS[cell.target]
	tick.visible = complete
	tooltip_text = tr("challenge.slot") % [index + 1, cell.coins.size()]
	if cell.target > 0:
		tooltip_text += " · " + tr("challenge.target") % cell.target
	focus_mode = Control.FOCUS_NONE if complete else Control.FOCUS_ALL


func select_coins(count: int) -> void:
	_stop_selection()
	_selected_count = count
	z_index = 10 if count > 0 else 0
	_selection_tween = create_tween().set_parallel(true)
	for offset in range(coin_views.size()):
		var selected := offset >= coin_views.size() - count
		coin_views[offset].set_floating(selected)
		var target := coin_position(offset) - Vector2(0, 35 if selected else 0)
		_selection_tween.tween_property(coin_views[offset], "position", target, 0.117).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if coin_views.is_empty():
		_selection_tween.kill()


func take_tail(count: int) -> Array:
	_stop_selection()
	var moved: Array = []
	for offset in range(coin_views.size() - count, coin_views.size()):
		coin_views[offset].set_floating(false)
		moved.append(coin_views[offset])
	coin_views.resize(coin_views.size() - count)
	return moved


func hide_tail(count: int) -> void:
	for offset in range(coin_views.size() - count, coin_views.size()):
		coin_views[offset].hide()
	tick.hide()


func shake_selected() -> Tween:
	_stop_selection()
	var tween := create_tween().set_parallel(true)
	for offset in range(coin_views.size() - _selected_count, coin_views.size()):
		var view := coin_views[offset]
		view.set_floating(false)
		var origin := coin_position(offset)
		tween.tween_property(view, "position:y", origin.y, 0.117)
		for step in range(4):
			var values := [0.0, -10.0, 10.0, -10.0, 0.0]
			tween.tween_property(view, "position:x", origin.x + values[step + 1], 1.0 / 12.0).from(origin.x + values[step]).set_delay(step / 12.0)
	_selected_count = 0
	return tween


func prepare_show() -> void:
	coin_parent.modulate.a = 0
	_mask.modulate.a = 0


func play_show(tween: Tween, delay: float) -> void:
	coin_parent.position = COIN_ORIGIN - Vector2(0, 45)
	coin_parent.scale = Vector2.ONE * 1.3
	tween.tween_property(coin_parent, "position", COIN_ORIGIN, 0.15).set_delay(delay)
	tween.tween_property(coin_parent, "scale", Vector2.ONE, 0.15).set_delay(delay)
	tween.tween_property(coin_parent, "modulate:a", 1.0, 0.15).set_delay(delay)
	tween.tween_callback(_mask.set_modulate.bind(Color.WHITE)).set_delay(delay + 0.15)


func show_target_light() -> void:
	# Light1 uses the captured emitter already ported for normal reveal effects.
	FX.particles(self, Vector2(55, 100), "reveal")


func play_success(tween: Tween, delay: float) -> void:
	if coin_views.is_empty():
		return
	tick.hide()
	tween.tween_callback(_start_success_light).set_delay(delay)
	tween.tween_property(coin_parent, "position:y", COIN_ORIGIN.y - 45, 0.1).set_delay(delay)
	tween.tween_property(coin_parent, "position:y", COIN_ORIGIN.y, 0.1).from(COIN_ORIGIN.y - 45).set_delay(delay + 0.1)
	tween.tween_callback(_light.hide).set_delay(delay + 0.2)


func _start_success_light() -> void:
	for child in _light.get_children():
		child.free()
	_light.show()
	var mask := _texture(preload(ROOT + "Texture/skin/CoinMask.png"), Vector2(-51, -129.65), Vector2(102.2, 237.5))
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://shaders/challenge_coin_light.gdshader")
	shader.set_shader_parameter("streak_texture", preload(ROOT + "ui/LaserLight.png"))
	mask.material = shader
	_light.add_child(mask)
	if _light_tween:
		_light_tween.kill()
	_light_tween = create_tween().set_parallel(true)
	_light_tween.tween_method(func(v: Vector2): shader.set_shader_parameter("sweep_offset", v), Vector2(-199.9, -212.5), Vector2(-0.9, -11.7), 0.25).set_delay(0.5)
	_light_tween.tween_method(func(v: Vector2): shader.set_shader_parameter("sweep_offset", v), Vector2(-0.9, -11.7), Vector2(168, 140), 5.0 / 12.0).set_delay(0.75)
	_light_tween.tween_property(mask, "modulate:a", 40.0 / 255.0, 1.0 / 6.0).from(80.0 / 255.0).set_delay(0.5)
	_light_tween.tween_property(mask, "modulate:a", 0.0, 5.0 / 12.0).set_delay(2.0 / 3.0)
	var particles := ParticleView.new()
	particles.configure(WAR_PARTICLES, false)
	_light.add_child(particles)


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


func _exit_tree() -> void:
	_stop_selection()
	if _light_tween:
		_light_tween.kill()
