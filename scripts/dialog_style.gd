extends RefCounted
const Ceramic = preload("res://scripts/ceramic_skin.gd")
## Ceramic borders and text padding are independent.

const UI := Ceramic.UI
const BODY_COLOR := Ceramic.INK
const BUTTONS := {
	"blue": preload(UI + "Btn_blue_25px.png"),
	"yellow": preload(UI + "Btn_yellow_25px.png"),
	"green": preload(UI + "Btn_green_25px.png"),
	"rescue": preload(UI + "Btn_Ad_broad.png"),
}


static func apply_button(button: Button, tone: String = "blue", font_size: int = 40) -> void:
	button.add_theme_font_override("font", Ceramic.FONT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Ceramic.INK)
	button.add_theme_color_override("font_disabled_color", Color("777c76"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = BUTTONS.get(tone, BUTTONS.blue)
		if tone != "rescue":
			style.texture_margin_left = Ceramic.BUTTON_MARGIN
			style.texture_margin_right = Ceramic.BUTTON_MARGIN
			style.texture_margin_top = Ceramic.BUTTON_MARGIN
			style.texture_margin_bottom = Ceramic.BUTTON_MARGIN
		style.content_margin_left = 22
		style.content_margin_right = 22
		var pressed: bool = state in ["pressed", "hover_pressed"]
		style.content_margin_top = 12 if pressed else 6
		style.content_margin_bottom = 12 if pressed else 18
		if pressed:
			style.modulate_color = Color(0.9, 0.9, 0.9)
		elif state == "hover":
			style.modulate_color = Color(1.04, 1.04, 1.04)
		elif state == "disabled":
			style.modulate_color = Color(0.7, 0.7, 0.75)
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(1, 1, 1, 0.65)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(48 if tone == "rescue" else 30)
	focus.set_expand_margin_all(3)
	button.add_theme_stylebox_override("focus", focus)
	fit_button_text(button, font_size)


static func fit_button_text(button: Button, preferred: int = 40) -> void:
	var available := maxf(button.size.x, button.custom_minimum_size.x) - 44
	var font := button.get_theme_font("font")
	var text := button.tr(button.text)
	var fitted := preferred
	while fitted > 26 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > available:
		fitted -= 1
	button.add_theme_font_size_override("font_size", fitted)


static func panel(dimensions: Vector2) -> NinePatchRect:
	var view := NinePatchRect.new()
	view.texture = preload(UI + "PanelBG.png")
	view.size = dimensions
	view.patch_margin_left = Ceramic.PANEL_MARGIN
	view.patch_margin_top = Ceramic.PANEL_MARGIN
	view.patch_margin_right = Ceramic.PANEL_MARGIN
	view.patch_margin_bottom = Ceramic.PANEL_MARGIN
	return view


static func title(view: Label) -> void:
	view.clip_text = true
	view.add_theme_color_override("font_color", Ceramic.INK)
	fit_label(view, 370, 45)


static func fit_label(view: Label, available: float, preferred: int) -> void:
	var font := view.get_theme_font("font")
	var fitted := preferred
	while fitted > 26 and font.get_string_size(view.tr(view.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > available:
		fitted -= 1
	view.add_theme_font_size_override("font_size", fitted)


static func close_button(callback: Callable) -> TextureButton:
	var view := TextureButton.new()
	view.size = Vector2(81, 81)
	view.texture_normal = preload(UI + "Btn_Quit.png")
	view.ignore_texture_size = true
	view.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	view.tooltip_text = TranslationServer.translate("关闭")
	view.pressed.connect(callback)
	return view
