extends ColorRect
## Cover the viewport even when a modal belongs to a centered, scaled game layout.


func _ready() -> void:
	color = Color(0, 0, 0, 0.59)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_schedule_fit)
	visibility_changed.connect(_schedule_fit)
	_fit()


func _schedule_fit() -> void:
	_fit.call_deferred()


func _fit() -> void:
	var parent := get_parent() as CanvasItem
	var area := parent.get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = area.position
	size = area.size
