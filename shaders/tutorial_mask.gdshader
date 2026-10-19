shader_type canvas_item;
uniform vec4 hole_rect = vec4(0.0);
uniform sampler2D hole_mask : filter_linear;
void fragment() {
	vec2 local = (UV - hole_rect.xy) / max(hole_rect.zw, vec2(0.0001));
	float inside = step(0.0, local.x) * step(0.0, local.y) * step(local.x, 1.0) * step(local.y, 1.0);
	float hole = texture(hole_mask, clamp(local, vec2(0.0), vec2(1.0))).a * inside;
	COLOR = vec4(0.0, 0.0, 0.0, 0.65 * (1.0 - hole));
}
